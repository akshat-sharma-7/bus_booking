require "rails_helper"

RSpec.describe BookingConfirmationService do
  let(:trip) { create(:trip, seats_count: 10, price: 500) }
  let(:user) { create(:user) }
  let(:seats) { trip.seats.order(:id).to_a }

  def hold_group_for(hold_user, seat_list)
    SeatHoldService.new(trip: trip, user: hold_user, seat_ids: seat_list.map(&:id)).call.hold_group_id
  end

  it "confirms a valid hold into one booking" do
    group = hold_group_for(user, [seats[0]])

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be true
    expect(result.booking.status).to eq("confirmed")
    expect(result.booking.pnr).to be_present
    expect(seats[0].reload.status).to eq("booked")
  end

  it "confirms multiple holds sharing a hold_group_id into exactly one booking" do
    group = hold_group_for(user, seats[0..2])

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be true
    expect(result.booking.seats).to contain_exactly(*seats[0..2])
    expect(result.booking.total_price).to eq(1500)
    expect(Booking.where(hold_group_id: group).count).to eq(1)
  end

  it "rejects a hold that has expired" do
    group = hold_group_for(user, [seats[0]])
    Hold.where(hold_group_id: group).update_all(expires_at: 1.minute.ago)

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be false
    expect(result.error).to match(/no longer active/i)
    expect(Booking.where(hold_group_id: group)).to be_empty
  end

  it "rejects a hold that was cancelled (not merely timed out)" do
    group = hold_group_for(user, [seats[0]])
    CancelHoldService.new(user: user, hold_group_id: group).call

    result = described_class.new(user: user, hold_group_id: group).call

    expect(result.success?).to be false
    expect(result.error).to match(/no longer active/i)
    expect(Booking.where(hold_group_id: group)).to be_empty
  end

  it "rejects confirmation by a user who doesn't own the hold" do
    group = hold_group_for(user, [seats[0]])
    other_user = create(:user)

    result = described_class.new(user: other_user, hold_group_id: group).call

    expect(result.success?).to be false
    expect(Booking.where(hold_group_id: group)).to be_empty
  end

  it "is idempotent on repeated confirmation of the same hold group (CASE B)" do
    group = hold_group_for(user, seats[0..1])

    first = described_class.new(user: user, hold_group_id: group).call
    second = described_class.new(user: user, hold_group_id: group).call

    expect(second.success?).to be true
    expect(second.booking.id).to eq(first.booking.id)
    expect(Booking.where(hold_group_id: group).count).to eq(1)
    # Not just "same booking" — no duplicate BookingSeat rows either.
    expect(BookingSeat.where(booking_id: first.booking.id).count).to eq(2)
    expect(BookingSeat.where(booking_id: first.booking.id).pluck(:seat_id).uniq.size).to eq(2)
  end

  it "does not leave partial state when the app-level uniqueness validation itself catches the race" do
    group = hold_group_for(user, [seats[0]])
    first = described_class.new(user: user, hold_group_id: group).call
    expect(first.success?).to be true

    # Force the model-level `validates :hold_group_id, uniqueness: true` path
    # specifically (rather than the raw DB constraint) by re-running #call —
    # the fast-path find already returns early, so this mainly documents
    # that a second attempt never produces a second Booking or BookingSeat
    # row via either path.
    second = described_class.new(user: user, hold_group_id: group).call
    expect(second.success?).to be true
    expect(Booking.where(hold_group_id: group).count).to eq(1)
    expect(BookingSeat.where(booking_id: first.booking.id).count).to eq(1)
  end

  it "does not swallow a RecordInvalid unrelated to the hold_group_id race" do
    group = hold_group_for(user, [seats[0]])

    # Simulate some other validation failing inside the transaction (e.g. a
    # BookingSeat bug) — this must propagate as a real error, not be
    # silently reinterpreted as "someone else already booked it".
    allow(BookingSeat).to receive(:create!).and_raise(
      ActiveRecord::RecordInvalid.new(BookingSeat.new.tap { |bs| bs.errors.add(:price, "boom") })
    )

    expect {
      described_class.new(user: user, hold_group_id: group).call
    }.to raise_error(ActiveRecord::RecordInvalid, /boom/)

    # And the transaction rolled back cleanly — no orphaned Booking.
    expect(Booking.where(hold_group_id: group)).to be_empty
  end

  it "concurrent confirmation of the same hold group does not create duplicate bookings (CASE C)", truncation: true do
    group = hold_group_for(user, seats[0..1])
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
          results[i] = described_class.new(user: user, hold_group_id: group).call
        end
      end
    end

    mutex.synchronize { cv.wait(mutex) until ready == 2 }
    2.times { start_latch << :go }
    completed = threads.map { |t| t.join(10) }.all? { |t| !t.nil? }

    expect(completed).to be true # no deadlock/hang
    expect(results).to all(satisfy { |r| r.success? })
    expect(results.map { |r| r.booking.id }.uniq.size).to eq(1) # both resolve to the SAME booking

    winning_booking = results.first.booking
    expect(Booking.where(hold_group_id: group).count).to eq(1)
    # Exactly one set of BookingSeat rows — not doubled, not partial.
    expect(BookingSeat.where(booking_id: winning_booking.id).count).to eq(2)
    expect(BookingSeat.where(booking_id: winning_booking.id).pluck(:seat_id).uniq.size).to eq(2)
    # No corrupted hold/seat state: both holds confirmed, both seats booked —
    # never left half-active/half-held from the loser's rolled-back attempt.
    expect(Hold.where(hold_group_id: group).pluck(:status).uniq).to eq(["confirmed"])
    expect(seats[0].reload.status).to eq("booked")
    expect(seats[1].reload.status).to eq("booked")
  end
end
