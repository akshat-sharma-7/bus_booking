class BookingsController < ApplicationController
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
end
