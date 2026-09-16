# Cancels a confirmed Booking and frees its seats. Same idempotency/
# concurrency shape as RescheduleBookingService: a pessimistic lock on the
# booking row itself (not a DB constraint) is what makes this safe under a
# race — see IMPLEMENTATION_NOTES.md "Cancellation architecture".
class CancellationService
  MIN_HOURS_BEFORE_DEPARTURE = 1

  Result = Struct.new(:success?, :booking, :refund_amount, :error, keyword_init: true)

  class Failure < StandardError; end

  def initialize(user:, booking:)
    @user = user
    @booking = booking
  end

  def call
    cancelled = nil

    ActiveRecord::Base.transaction do
      # Locked first — the entire concurrency/idempotency guard, same
      # pattern as RescheduleBookingService. Scoped by user in the query
      # itself so a wrong-user attempt gets "not found", not a leak.
      original = Booking.where(id: booking.id, user: user).lock.includes(:trip).first
      raise Failure, "Booking not found" if original.nil?

      unless original.confirmed?
        raise Failure, "Only a confirmed booking can be cancelled (this one is #{original.status})"
      end

      if original.trip.departure_time < MIN_HOURS_BEFORE_DEPARTURE.hours.from_now
        raise Failure, "Cancellation is only allowed up to 1 hour before departure"
      end

      original.update!(status: :cancelled)

      original.booking_seats.each do |booking_seat|
        seat = booking_seat.seat.lock!
        seat.update!(status: :available)
      end

      cancelled = original
    end

    Result.new(success?: true, booking: cancelled, refund_amount: cancelled.refund_amount)
  rescue Failure => e
    Result.new(success?: false, error: e.message)
  end

  private

  attr_reader :user, :booking
end
