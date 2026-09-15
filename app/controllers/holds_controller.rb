class HoldsController < ApplicationController
  before_action :set_trip

  def create
    result = SeatHoldService.new(trip: @trip, user: Current.user, seat_ids: params[:seat_ids]).call

    if result.success?
      redirect_to trip_hold_path(@trip, result.hold_group_id)
    else
      redirect_to trip_path(@trip), alert: result.error
    end
  end

  # :id is the hold_group_id (a UUID), not a single Hold's own id — it
  # identifies the whole set of seats requested together.
  def show
    @holds = Hold.where(hold_group_id: params[:id], user: Current.user, trip: @trip)
                 .includes(:seat).order(:id)

    if @holds.empty?
      redirect_to trip_path(@trip), alert: "Hold not found" and return
    end

    @hold_group_id = params[:id]
    @expires_at = @holds.first.expires_at
    @expired = @holds.first.status != "active" || @expires_at <= Time.current
  end

  # :id is the hold_group_id, same as #show.
  def destroy
    result = CancelHoldService.new(user: Current.user, hold_group_id: params[:id]).call

    if result.success?
      redirect_to trip_path(@trip), notice: "Hold cancelled — seats are available again."
    else
      redirect_to trip_path(@trip), alert: result.error
    end
  end

  private

  def set_trip
    @trip = Trip.find(params[:trip_id])
  end
end
