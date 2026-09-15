# Turns a seat-selection request into one or more Hold rows sharing a single
# hold_group_id — see IMPLEMENTATION_NOTES.md "Concurrency decisions" for why
# locking order and the DB constraint both matter here.
class SeatHoldService
  MAX_SEATS = 6
  HOLD_DURATION = 5.minutes

  Result = Struct.new(:success?, :hold_group_id, :holds, :error, keyword_init: true)

  # Raised (and rescued) only to unwind the transaction with a human-readable
  # reason — not meant to escape #call.
  class Failure < StandardError; end

  def initialize(trip:, user:, seat_ids:)
    @trip = trip
    @user = user
    @seat_ids = Array(seat_ids).map(&:to_i).uniq
  end

  def call
    return failure("Select at least 1 seat") if seat_ids.empty?
    return failure("You can select at most #{MAX_SEATS} seats") if seat_ids.size > MAX_SEATS

    hold_group_id = SecureRandom.uuid
    holds = []

    ActiveRecord::Base.transaction do
      # Deterministic order (primary key ascending), NOT the order seat_ids
      # arrived in — this is what prevents a deadlock when two requests lock
      # an overlapping set of seats in different orders. See
      # IMPLEMENTATION_NOTES.md "deterministic lock ordering".
      seats = Seat.where(id: seat_ids, trip_id: trip.id).order(:id).lock.to_a

      if seats.size != seat_ids.size
        raise Failure, "One or more selected seats could not be found for this trip"
      end

      unavailable = seats.reject(&:available?)
      if unavailable.any?
        raise Failure, "Seat(s) #{unavailable.map(&:seat_number).join(', ')} are no longer available"
      end

      seats.each do |seat|
        holds << Hold.create!(user: user, trip: trip, seat: seat,
                               hold_group_id: hold_group_id, expires_at: HOLD_DURATION.from_now)
        seat.update!(status: :held)
      end
    end

    # Enqueued AFTER the transaction commits, not inside it — if this were
    # inside the `transaction do...end` block and something later in it
    # raised, we'd have scheduled expiry for Holds that were rolled back and
    # never actually existed.
    HoldExpiryJob.set(wait: HOLD_DURATION).perform_later(hold_group_id)

    Result.new(success?: true, hold_group_id: hold_group_id, holds: holds)
  rescue Failure => e
    failure(e.message)
  rescue ActiveRecord::RecordNotUnique
    # Belt-and-suspenders: the row lock above should already serialize
    # concurrent attempts on the same seat, but if the partial unique index
    # is ever the thing that catches it instead, surface the same message.
    failure("One or more selected seats were just taken by another user")
  end

  private

  attr_reader :trip, :user, :seat_ids

  def failure(message)
    Result.new(success?: false, error: message)
  end
end
