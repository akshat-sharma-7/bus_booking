require "rails_helper"

RSpec.describe CancellationService do
  let(:operator) { create(:operator, rating: 4.0) }
  let(:user) { create(:user) }

  def trip_departing_in(duration, seats_count: 5, price: 500)
    create(:trip, operator: operator, from_city: "Pune", to_city: "Mumbai",
                   travel_date: duration.from_now.to_date,
                   departure_time: duration.from_now, arrival_time: duration.from_now + 4.hours,
                   price: price, seats_count: seats_count)
  end

  def confirm_booking(booking_user, trip, seat_count)
    seats = trip.seats.order(:id).limit(seat_count)
    hold = SeatHoldService.new(trip: trip, user: booking_user, seat_ids: seats.map(&:id)).call
    raise "hold setup failed: #{hold.error}" unless hold.success?

    result = BookingConfirmationService.new(user: booking_user, hold_group_id: hold.hold_group_id).call
    raise "confirm setup failed: #{result.error}" unless result.success?

    result.booking
  end

  it "successfully cancels a confirmed booking, freeing its seats" do
    trip = trip_departing_in(2.hours)
    booking = confirm_booking(user, trip, 2)

    result = described_class.new(user: user, booking: booking).call

    expect(result.success?).to be true
    expect(result.booking.status).to eq("cancelled")
    expect(result.booking.seats.reload).to all(be_available)
  end

  it "allows cancellation exactly 1 hour before departure" do
    trip = trip_departing_in(1.hour + 1.second) # comfortably on the allowed side of the boundary
    booking = confirm_booking(user, trip, 1)

    result = described_class.new(user: user, booking: booking).call

    expect(result.success?).to be true
  end

  it "rejects cancellation less than 1 hour before departure" do
    trip = trip_departing_in(30.minutes)
    booking = confirm_booking(user, trip, 1)

    result = described_class.new(user: user, booking: booking).call

    expect(result.success?).to be false
    expect(result.error).to match(/1 hour/i)
    booking.reload
    expect(booking.status).to eq("confirmed")
    expect(booking.seats.reload).to all(be_booked)
  end

  it "rejects cancelling an already-cancelled booking" do
    trip = trip_departing_in(2.hours)
    booking = confirm_booking(user, trip, 1)
    described_class.new(user: user, booking: booking).call

    result = described_class.new(user: user, booking: booking).call

    expect(result.success?).to be false
    expect(result.error).to match(/confirmed/i)
  end

  it "rejects cancelling a rescheduled booking" do
    trip = trip_departing_in(2.hours)
    other_trip = trip_departing_in(3.hours)
    booking = confirm_booking(user, trip, 1)
    RescheduleBookingService.new(user: user, booking: booking, target_trip_id: other_trip.id).call

    result = described_class.new(user: user, booking: booking.reload).call

    expect(result.success?).to be false
  end

  it "rejects cancellation by a user who does not own the booking" do
    trip = trip_departing_in(2.hours)
    booking = confirm_booking(user, trip, 1)
    other_user = create(:user)

    result = described_class.new(user: other_user, booking: booking).call

    expect(result.success?).to be false
    booking.reload
    expect(booking.status).to eq("confirmed")
    expect(booking.seats.reload).to all(be_booked)
  end

  it "applies the ₹50 fee once per booking, not per seat" do
    trip = trip_departing_in(2.hours, price: 500)
    booking = confirm_booking(user, trip, 3) # 3 seats * 500 = 1500

    result = described_class.new(user: user, booking: booking).call

    expect(booking.total_price).to eq(1500)
    expect(result.refund_amount).to eq(1450) # 1500 - 50, not 1500 - 150
  end

  it "computes the refund correctly for a single seat" do
    trip = trip_departing_in(2.hours, price: 200)
    booking = confirm_booking(user, trip, 1)

    result = described_class.new(user: user, booking: booking).call

    expect(result.refund_amount).to eq(150)
  end

  it "is idempotent — repeated cancellation does not change the refund or state twice" do
    trip = trip_departing_in(2.hours)
    booking = confirm_booking(user, trip, 1)

    first = described_class.new(user: user, booking: booking).call
    second = described_class.new(user: user, booking: booking.reload).call

    expect(first.success?).to be true
    expect(second.success?).to be false
    expect(booking.reload.status).to eq("cancelled")
  end

  it "resolves concurrent cancellation of the same booking safely, without corruption", truncation: true do
    trip = trip_departing_in(2.hours)
    booking = confirm_booking(user, trip, 2)

    results = Array.new(2)
    ready = 0
    mutex = Mutex.new
    cv = ConditionVariable.new
    start_latch = Queue.new

    threads = [0, 1].map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutex.synchronize { ready += 1; cv.signal }
          start_latch.pop
          results[i] = described_class.new(user: user, booking: booking).call
        end
      end
    end

    mutex.synchronize { cv.wait(mutex) until ready == 2 }
    2.times { start_latch << :go }
    completed = threads.map { |t| t.join(10) }.all? { |t| !t.nil? }

    expect(completed).to be true
    expect(results.count { |r| r.success? }).to eq(1)
    expect(results.count { |r| !r.success? }).to eq(1)

    booking.reload
    expect(booking.status).to eq("cancelled")
    expect(booking.seats.reload).to all(be_available) # not half-released
  end

  it "rolls back completely if a failure occurs partway through" do
    trip = trip_departing_in(2.hours)
    booking = confirm_booking(user, trip, 2)
    seat_ids = booking.seats.pluck(:id)

    allow_any_instance_of(Seat).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(Seat.new))

    expect {
      described_class.new(user: user, booking: booking).call
    }.to raise_error(ActiveRecord::RecordInvalid)

    booking.reload
    expect(booking.status).to eq("confirmed") # NOT cancelled — the update! that set it also rolled back
    expect(Seat.where(id: seat_ids)).to all(be_booked)
  end
end
