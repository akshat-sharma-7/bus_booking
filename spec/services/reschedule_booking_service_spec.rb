require "rails_helper"

RSpec.describe RescheduleBookingService do
  let(:operator) { create(:operator, rating: 4.0) }
  let(:other_operator) { create(:operator, rating: 4.0) }
  let(:user) { create(:user) }

  # The trip factory's `departure_time` default doesn't vary with
  # `travel_date`, so multiple same-operator/same-route trips in one example
  # need explicit, distinct departure times or they collide on
  # index_trips_on_operator_route_departure. This helper keeps that out of
  # every example.
  def same_route_trip(days_from_now:, op: operator, from: "Pune", to: "Mumbai", **attrs)
    departure = days_from_now.days.from_now.change(hour: 9)
    create(:trip, operator: op, from_city: from, to_city: to, travel_date: departure.to_date,
                   departure_time: departure, arrival_time: departure + 4.hours, seats_count: 5, **attrs)
  end

  let(:original_trip) { same_route_trip(days_from_now: 1, price: 500) }
  let(:target_trip) { same_route_trip(days_from_now: 2, price: 600) } # same route + operator, different date

  def confirm_booking(booking_user, trip, seat_count)
    seats = trip.seats.order(:id).limit(seat_count)
    hold = SeatHoldService.new(trip: trip, user: booking_user, seat_ids: seats.map(&:id)).call
    raise "hold setup failed: #{hold.error}" unless hold.success?

    result = BookingConfirmationService.new(user: booking_user, hold_group_id: hold.hold_group_id).call
    raise "confirm setup failed: #{result.error}" unless result.success?

    result.booking
  end

  # CASE A
  it "successfully reschedules a confirmed booking to a same-route, same-operator trip" do
    original = confirm_booking(user, original_trip, 2)

    result = described_class.new(user: user, booking: original, target_trip_id: target_trip.id).call

    expect(result.success?).to be true
    expect(result.booking.status).to eq("confirmed")
    expect(result.booking.trip).to eq(target_trip)
    expect(result.booking.seats.count).to eq(2) # same number of seats
    expect(result.booking.total_price).to eq(target_trip.price * 2)

    original.reload
    expect(original.status).to eq("rescheduled")
    expect(original.replacement_booking_id).to eq(result.booking.id)
    expect(original.seats.reload).to all(be_available)
    expect(result.booking.seats).to all(be_booked)
  end

  # CASE B
  it "rejects a target trip on a different route" do
    original = confirm_booking(user, original_trip, 1)
    wrong_route_trip = same_route_trip(days_from_now: 3, from: "Delhi", to: "Jaipur")

    result = described_class.new(user: user, booking: original, target_trip_id: wrong_route_trip.id).call

    expect(result.success?).to be false
    expect(result.error).to match(/same route/i)
    original.reload
    expect(original.status).to eq("confirmed")
    expect(original.seats.reload).to all(be_booked)
    expect(Booking.where(trip: wrong_route_trip)).to be_empty
  end

  # CASE C
  it "rejects a target trip with a different operator" do
    original = confirm_booking(user, original_trip, 1)
    wrong_operator_trip = same_route_trip(days_from_now: 3, op: other_operator)

    result = described_class.new(user: user, booking: original, target_trip_id: wrong_operator_trip.id).call

    expect(result.success?).to be false
    expect(result.error).to match(/same operator/i)
    original.reload
    expect(original.status).to eq("confirmed")
  end

  # CASE D
  it "rejects rescheduling an already-cancelled booking" do
    original = confirm_booking(user, original_trip, 1)
    original.update!(status: :cancelled)

    result = described_class.new(user: user, booking: original, target_trip_id: target_trip.id).call

    expect(result.success?).to be false
    expect(Booking.where(trip: target_trip)).to be_empty
  end

  # CASE E
  it "rejects rescheduling an already-rescheduled booking and does not create a second replacement" do
    original = confirm_booking(user, original_trip, 1)
    first = described_class.new(user: user, booking: original, target_trip_id: target_trip.id).call
    expect(first.success?).to be true

    another_target = same_route_trip(days_from_now: 4)
    second = described_class.new(user: user, booking: original.reload, target_trip_id: another_target.id).call

    expect(second.success?).to be false
    expect(original.reload.replacement_booking_id).to eq(first.booking.id) # unchanged
    expect(Booking.where(trip: another_target)).to be_empty
    expect(user.bookings.count).to eq(2) # original + first replacement only
  end

  # CASE F
  it "rejects when the target trip does not have enough available seats" do
    original = confirm_booking(user, original_trip, 3)
    small_target = same_route_trip(days_from_now: 3)
    # Only 2 of 5 left available on the target.
    small_target.seats.order(:id).limit(3).each { |s| s.update!(status: :booked) }

    result = described_class.new(user: user, booking: original, target_trip_id: small_target.id).call

    expect(result.success?).to be false
    expect(result.error).to match(/enough available seats/i)
    original.reload
    expect(original.status).to eq("confirmed")
    expect(original.seats.reload).to all(be_booked)
    expect(Booking.where(trip: small_target)).to be_empty
    # The 2 seats that WERE available on the target must not have been
    # left half-locked/booked by the aborted attempt.
    expect(small_target.seats.reload.where(status: :available).count).to eq(2)
  end

  # CASE G
  it "rejects rescheduling when the requesting user does not own the booking" do
    original = confirm_booking(user, original_trip, 1)
    other_user = create(:user)

    result = described_class.new(user: other_user, booking: original, target_trip_id: target_trip.id).call

    expect(result.success?).to be false
    original.reload
    expect(original.status).to eq("confirmed")
    expect(Booking.where(trip: target_trip)).to be_empty
  end

  # CASE H
  it "is safe against a repeated (sequential) reschedule request" do
    original = confirm_booking(user, original_trip, 1)

    first = described_class.new(user: user, booking: original, target_trip_id: target_trip.id).call
    second = described_class.new(user: user, booking: original.reload, target_trip_id: target_trip.id).call

    expect(first.success?).to be true
    expect(second.success?).to be false
    expect(Booking.where(trip: target_trip).count).to eq(1)
    expect(user.bookings.count).to eq(2)
  end

  # CASE I
  it "resolves a concurrent double-reschedule of the same booking into exactly one replacement", truncation: true do
    original = confirm_booking(user, original_trip, 1)
    target_a = same_route_trip(days_from_now: 5)
    target_b = same_route_trip(days_from_now: 6)

    results = Array.new(2)
    ready = 0
    mutex = Mutex.new
    cv = ConditionVariable.new
    start_latch = Queue.new

    threads = [target_a, target_b].each_with_index.map do |target, i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutex.synchronize { ready += 1; cv.signal }
          start_latch.pop
          results[i] = described_class.new(user: user, booking: original, target_trip_id: target.id).call
        end
      end
    end

    mutex.synchronize { cv.wait(mutex) until ready == 2 }
    2.times { start_latch << :go }
    completed = threads.map { |t| t.join(10) }.all? { |t| !t.nil? }

    expect(completed).to be true # no deadlock/hang
    expect(results.count { |r| r.success? }).to eq(1) # exactly one winner
    expect(results.count { |r| !r.success? }).to eq(1)

    original.reload
    expect(original.status).to eq("rescheduled")
    winner = results.find(&:success?).booking
    expect(original.replacement_booking_id).to eq(winner.id)
    # No partial/duplicate replacement anywhere.
    expect(Booking.where(trip: [target_a, target_b]).count).to eq(1)
    expect(BookingSeat.where(booking_id: winner.id).count).to eq(1)
  end

  # CASE J
  it "rolls back completely if a failure occurs partway through" do
    original = confirm_booking(user, original_trip, 2)
    original_seat_ids = original.seats.pluck(:id)

    # Force a failure AFTER the replacement Booking row would be created but
    # while still inside the transaction, simulating a mid-operation error.
    allow_any_instance_of(BookingSeat).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(BookingSeat.new))

    expect {
      described_class.new(user: user, booking: original, target_trip_id: target_trip.id).call
    }.to raise_error(ActiveRecord::RecordInvalid)

    original.reload
    expect(original.status).to eq("confirmed")
    expect(original.replacement_booking_id).to be_nil
    expect(Seat.where(id: original_seat_ids)).to all(be_booked)
    expect(Booking.where(trip: target_trip)).to be_empty
    expect(BookingSeat.where(seat_id: target_trip.seats.pluck(:id))).to be_empty
    # Target seats were locked-then-rolled-back, not left booked.
    expect(target_trip.seats.reload.where(status: :available).count).to eq(5)
  end
end
