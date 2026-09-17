class TripsController < ApplicationController
  # Browsing/searching trips doesn't require login — only holding a seat and
  # confirming a booking do (those controllers keep the default require-auth).
  allow_unauthenticated_access only: %i[index show]

  def index
    @results = TripSearchService.new(search_params).call
    @search_params = search_params
    @bus_types = Trip.bus_types.keys
    @amenity_options = Trip::AMENITY_OPTIONS
    @cities = popular_cities
  end

  def show
    @trip = Trip.includes(:operator, :seats).find(params[:id])
    @seats = @trip.seats.order(:seat_number)
  end

  private

  def popular_cities
    (Trip::POPULAR_CITIES + Trip.distinct.pluck(:from_city) + Trip.distinct.pluck(:to_city)).uniq.sort
  end

  def search_params
    params.permit(:from_city, :to_city, :travel_date, :min_rating, :price_min, :price_max,
                   :bus_type, amenities: []).to_h.symbolize_keys
  end
end
