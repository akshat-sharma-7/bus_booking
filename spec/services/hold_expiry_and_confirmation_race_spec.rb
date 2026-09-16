require "rails_helper"

# Two related races around HoldExpiryService — see IMPLEMENTATION_NOTES.md
# "Concurrency decisions" for why row locking is what serializes these
# rather than either side trusting a timestamp read before acquiring a lock.
RSpec.describe "Hold expiry races" do
  let(:trip) { create(:trip, seats_count: 5) }
  let(:user) { create(:user) }
  let(:seat) { trip.seats.first }

  def race(&block)
    ready = 0
    mutex = Mutex.new
    cv = ConditionVariable.new
    start_latch = Queue.new
    results = Array.new(2)

    threads = [0, 1].map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mutex.synchronize { ready += 1; cv.signal }
          start_latch.pop
          results[i] = block.call(i)
        end
      end
    end

    mutex.synchronize { cv.wait(mutex) until ready == 2 }
    2.times { start_latch << :go }
    completed = threads.map { |t| t.join(10) }.all? { |t| !t.nil? }
    [results, completed]
  end

  describe "expiry vs. booking confirmation, run concurrently on an already-time-expired hold" do
    it "confirmation is always rejected and never corrupts the seat expiry frees", truncation: true do
      hold = create(:hold, user: user, trip: trip, seat: seat, status: :active, expires_at: 1.minute.ago)

      (confirm_result, _), completed = race do |i|
        i.zero? ? BookingConfirmationService.new(user: user, hold_group_id: hold.hold_group_id).call
                : HoldExpiryService.new(hold_group_id: hold.hold_group_id).call
      end

      expect(completed).to be true # no deadlock/hang
      # BookingConfirmationService independently checks expires_at under its
      # own lock — it doesn't need HoldExpiryService to have already run to
      # correctly refuse a time-expired hold, so this side of the race is
      # deterministic by design, not a coin flip.
      expect(confirm_result.success?).to be false
      expect(hold.reload.status).to eq("expired")
      expect(seat.reload.status).to eq("available")
      expect(Booking.where(hold_group_id: hold.hold_group_id)).to be_empty
    end
  end

  describe "cancel vs. expiry, run concurrently on a hold that is both cancellable and past due" do
    it "whichever wins leaves a consistent, non-corrupted terminal state", truncation: true do
      hold = create(:hold, user: user, trip: trip, seat: seat, status: :active, expires_at: 1.minute.ago)

      results, completed = race do |i|
        if i.zero?
          CancelHoldService.new(user: user, hold_group_id: hold.hold_group_id).call
        else
          HoldExpiryService.new(hold_group_id: hold.hold_group_id).call
        end
      end

      expect(completed).to be true
      expect(results[0].success?).to be true # CancelHoldService: released or no-op, either way "success"

      # Both scope their initial lock query by status: "active", so whichever
      # transaction commits first, the other's query simply returns no rows
      # to act on — never two competing writers on the same row.
      expect(%w[released expired]).to include(hold.reload.status)
      expect(seat.reload.status).to eq("available") # freed either way — no corruption
    end
  end
end
