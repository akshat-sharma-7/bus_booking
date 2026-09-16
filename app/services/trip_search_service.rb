# Pairs a Trip with its live available-seat count. Not an ActiveRecord model —
# purely a display-layer value object, so search results never carry a
# cached/stale availability number by accident.
TripSearchResult = Struct.new(:trip, :available_seats_count)

class TripSearchService
  CACHE_TTL = 60.seconds

  def initialize(params)
    @params = params
  end

  def call
    trips = Trip.where(id: cached_trip_ids).includes(:operator).order(:departure_time)
    seat_counts = Seat.where(trip_id: trips.map(&:id), status: :available).group(:trip_id).count

    trips.map { |trip| TripSearchResult.new(trip, seat_counts.fetch(trip.id, 0)) }
  end

  private

  attr_reader :params

  # Only the trip-metadata query result (which rows match) is cached — never
  # the seat counts computed above, which are always read fresh. See
  # IMPLEMENTATION_NOTES.md "Caching Strategy" for why.
  def cached_trip_ids
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { matching_trips.pluck(:id) }
  end

  def cache_key
    "trip_search/v1/#{normalized_params.to_a.sort.hash}"
  end

  def matching_trips
    scope = Trip.all
    scope = scope.for_route(params[:from_city], params[:to_city]) if from_city.present? && to_city.present?
    scope = scope.on_date(travel_date) if travel_date.present?
    scope = scope.min_operator_rating(min_rating) if min_rating.present?
    scope = scope.price_between(price_min, price_max) if price_min.present? || price_max.present?
    scope = scope.with_bus_type(bus_type) if bus_type.present?
    scope = scope.with_amenities(amenities) if amenities.present?
    scope
  end

  def normalized_params
    {
      from_city: from_city, to_city: to_city, travel_date: travel_date&.iso8601,
      min_rating: min_rating, price_min: price_min, price_max: price_max,
      bus_type: bus_type, amenities: amenities.sort
    }
  end

  def from_city = params[:from_city].presence&.strip
  def to_city = params[:to_city].presence&.strip

  def travel_date
    Date.parse(params[:travel_date]) if params[:travel_date].present?
  rescue ArgumentError
    nil
  end

  def min_rating = params[:min_rating].presence&.to_f
  def price_min = params[:price_min].presence&.to_f
  def price_max = params[:price_max].presence&.to_f

  def bus_type
    value = params[:bus_type].presence
    value if value.in?(Trip.bus_types.keys)
  end

  def amenities
    Array(params[:amenities]).reject(&:blank?)
  end
end
