class BookingsController < ApplicationController
  def index
    @bookings = Current.user.bookings.includes(trip: :operator, booking_seats: :seat).order(created_at: :desc)
  end

  def create
    result = BookingConfirmationService.new(user: Current.user, hold_group_id: params[:hold_group_id]).call

    if result.success?
      redirect_to booking_path(result.booking)
    else
      trip = Hold.where(hold_group_id: params[:hold_group_id]).first&.trip
      redirect_to(trip ? trip_path(trip) : trips_path, alert: result.error)
    end
  end

  def show
    @booking = Current.user.bookings.includes(trip: :operator, booking_seats: :seat).find(params[:id])
  end

  # GET — the target-trip picker. The list here is just a convenience filter
  # for the UI (same route + operator + not the current trip); it does not
  # duplicate RescheduleBookingService's validation as a source of truth —
  # the service re-checks everything (including seat availability) itself.
  def reschedule_form
    @booking = Current.user.bookings.find(params[:id])
    @target_trips = Trip.where(operator_id: @booking.trip.operator_id)
                         .for_route(@booking.trip.from_city, @booking.trip.to_city)
                         .where.not(id: @booking.trip_id)
                         .order(:departure_time)
  end

  # POST — the actual submit.
  def reschedule
    booking = Current.user.bookings.find(params[:id])
    result = RescheduleBookingService.new(user: Current.user, booking: booking, target_trip_id: params[:trip_id]).call

    if result.success?
      redirect_to booking_path(result.booking), notice: "Booking rescheduled successfully."
    else
      redirect_to reschedule_booking_path(booking), alert: result.error
    end
  end

  def cancel
    booking = Current.user.bookings.find(params[:id])
    result = CancellationService.new(user: Current.user, booking: booking).call

    if result.success?
      redirect_to booking_path(result.booking),
                  notice: "Booking cancelled. Cancellation fee: ₹#{Booking::CANCELLATION_FEE}. Refund amount: ₹#{result.refund_amount.to_i}."
    else
      redirect_to booking_path(booking), alert: result.error
    end
  end
end
