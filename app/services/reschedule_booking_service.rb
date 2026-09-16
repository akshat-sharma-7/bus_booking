# Moves a confirmed Booking to a different trip on the same route/operator,
# preserving the seat count. See IMPLEMENTATION_NOTES.md "Reschedule
# architecture" for why old seats are only released after the replacement is
# fully created, and why locking the original Booking row (not a
# hold_group_id-style DB constraint) is what makes this idempotent under a
# race.
class RescheduleBookingService
  Result = Struct.new(:success?, :booking, :error, keyword_init: true)

  class Failure < StandardError; end

  def initialize(user:, booking:, target_trip_id:)
    @user = user
    @booking = booking
    @target_trip_id = target_trip_id
  end

  def call
    replacement = nil

    ActiveRecord::Base.transaction do
      # Locked FIRST, before anything else — this single row lock is the
      # entire concurrency guard for this operation. Whichever concurrent
      # reschedule request acquires it first proceeds; the other, once
      # unblocked, re-reads status as "rescheduled" and fails cleanly below.
      # Scoped by user in the query itself (not a post-load comparison) so a
      # wrong-user attempt gets the same "not found" as a bogus id — no leak.
      original = Booking.where(id: booking.id, user: user).lock.first
      raise Failure, "Booking not found" if original.nil?

      unless original.confirmed?
        raise Failure, "Only a confirmed booking can be rescheduled (this one is #{original.status})"
      end

      target_trip = Trip.find_by(id: target_trip_id)
      raise Failure, "Target trip not found" if target_trip.nil?

      original_trip = original.trip
      if target_trip.id == original_trip.id
        raise Failure, "Target trip must be different from the current trip"
      end
      if target_trip.operator_id != original_trip.operator_id
        raise Failure, "Target trip must be with the same operator"
      end
      if target_trip.from_city != original_trip.from_city || target_trip.to_city != original_trip.to_city
        raise Failure, "Target trip must be on the same route"
      end

      seat_count = original.booking_seats.count

      # Deterministic order (ascending id), same convention as
      # SeatHoldService/HoldExpiryService/CancelHoldService — avoids deadlock
      # if two reschedules concurrently target overlapping seats on the same
      # trip. Simplest-possible seat selection: any N available seats on the
      # target trip, not an attempt to preserve the original seat numbers —
      # see IMPLEMENTATION_NOTES.md for why.
      target_seats = Seat.where(trip_id: target_trip.id, status: :available)
                          .order(:id).lock.limit(seat_count).to_a

      if target_seats.size < seat_count
        raise Failure, "Target trip does not have enough available seats " \
                        "(needs #{seat_count}, #{target_seats.size} available)"
      end

      # Replacement created — and its seats marked booked — BEFORE the
      # original is touched at all. If anything above or below this line
      # raises, the whole transaction rolls back and the original booking
      # and its seats are completely untouched.
      replacement = Booking.create!(user: user, trip: target_trip, hold_group_id: SecureRandom.uuid,
                                     total_price: target_trip.price * seat_count)

      target_seats.each do |seat|
        BookingSeat.create!(booking: replacement, seat: seat, price: target_trip.price)
        seat.update!(status: :booked)
      end

      # Only now — replacement fully created and committed-within-this-
      # transaction — do we touch the original at all.
      original.update!(status: :rescheduled, replacement_booking: replacement)

      original.booking_seats.each do |booking_seat|
        seat = booking_seat.seat.lock!
        seat.update!(status: :available)
      end
    end

    success(replacement)
  rescue Failure => e
    failure(e.message)
  end

  private

  attr_reader :user, :booking, :target_trip_id

  def success(booking) = Result.new(success?: true, booking: booking)
  def failure(message) = Result.new(success?: false, error: message)
end
