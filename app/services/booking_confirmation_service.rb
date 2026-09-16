# Turns an active hold group into exactly one Booking, no matter how many
# times "Confirm" is submitted. See IMPLEMENTATION_NOTES.md "How idempotency
# works, precisely" for the reasoning behind the two-layer check below.
class BookingConfirmationService
  Result = Struct.new(:success?, :booking, :error, keyword_init: true)

  class Failure < StandardError; end
  # Not an error condition — raised to unwind the transaction when this
  # request loses a race to another confirmation of the SAME hold_group_id
  # (the other request's transaction already flipped these holds to
  # "confirmed" and committed before we acquired the lock).
  class AlreadyConfirmed < StandardError; end

  def initialize(user:, hold_group_id:)
    @user = user
    @hold_group_id = hold_group_id
  end

  def call
    # Cheap fast path for the common case (page refresh, double-click):
    # already confirmed by an earlier request, no locking needed at all.
    existing = find_existing_booking
    return success(existing) if existing

    booking = nil

    ActiveRecord::Base.transaction do
      holds = Hold.where(hold_group_id: hold_group_id, user: user)
                  .order(:id).lock.includes(:seat, :trip).to_a

      raise Failure, "Hold not found" if holds.empty?

      # Checked before the "expired" check: a hold that's already confirmed
      # is not active either, but it means a concurrent request for this
      # exact group won the race and committed while we were blocked on the
      # lock above — not that this group expired.
      raise AlreadyConfirmed if holds.any? { |h| h.status == "confirmed" }

      if holds.any? { |h| h.status != "active" || h.expired_by_time? }
        # Covers both "timed out" (HoldExpiryService got there first) and
        # "the user clicked Cancel Hold in another tab" (CancelHoldService
        # got there first, status == "released") — same outcome either way,
        # so one message rather than guessing which race was lost.
        raise Failure, "Your hold is no longer active. Please select seats again."
      end

      trip = holds.first.trip
      booking = Booking.create!(user: user, trip: trip, hold_group_id: hold_group_id,
                                 total_price: trip.price * holds.size)

      holds.each do |hold|
        BookingSeat.create!(booking: booking, seat: hold.seat, price: trip.price)
        hold.update!(status: :confirmed)
        hold.seat.update!(status: :booked)
      end
    end

    success(booking)
  rescue Failure => e
    failure(e.message)
  rescue AlreadyConfirmed
    recover_from_lost_race
  rescue ActiveRecord::RecordNotUnique => e
    # Narrowed to the specific constraint that can legitimately race here —
    # a blanket rescue would also swallow a RecordNotUnique from an unrelated
    # bug (e.g. a stray duplicate BookingSeat) and misreport it as "someone
    # else already booked it" instead of surfacing the real error.
    raise unless e.message.include?("index_bookings_on_hold_group_id")

    recover_from_lost_race
  rescue ActiveRecord::RecordInvalid => e
    # Same narrowing at the model-validation layer: only recover when this
    # is specifically the Booking's hold_group_id uniqueness validation
    # catching the race (belt-and-suspenders alongside the DB index above,
    # since the app-level validation runs first and usually wins). Any other
    # validation failure (bad price, missing trip, a genuine BookingSeat
    # bug, ...) is a real error and must not be silently reinterpreted as a
    # successful race recovery.
    raise unless e.record.is_a?(Booking) && e.record.errors[:hold_group_id].present?

    recover_from_lost_race
  end

  private

  attr_reader :user, :hold_group_id

  def find_existing_booking
    Booking.find_by(hold_group_id: hold_group_id, user: user)
  end

  # Another request for this exact hold_group_id won the race and committed
  # first — either we saw its "confirmed" holds under our own lock
  # (AlreadyConfirmed) or its INSERT beat ours to the unique index/validation
  # (RecordNotUnique/RecordInvalid). Either way, the transaction that raised
  # has already been rolled back and closed by Rails, so this query runs
  # cleanly (not inside a poisoned transaction) and returns what the winner
  # created — the caller sees success either way, per the idempotency
  # requirement.
  def recover_from_lost_race
    existing = find_existing_booking
    existing ? success(existing) : failure("Could not confirm booking")
  end

  def success(booking) = Result.new(success?: true, booking: booking)
  def failure(message) = Result.new(success?: false, error: message)
end
