class Trip < ApplicationRecord
  AMENITY_OPTIONS = %w[wifi charging blanket water_bottle reading_light tv].freeze

  # Guaranteed entries for the search form's From/To city dropdowns — kept
  # separate from whatever cities actually have trips right now (see
  # TripsController#popular_cities) so the dropdown is never empty on a
  # fresh/empty database and always includes these regardless of seed data.
  POPULAR_CITIES = %w[Indore Ujjain Bhopal Dewas Mumbai Pune Ahmedabad Delhi].freeze

  belongs_to :operator
  has_many :seats, dependent: :destroy
  has_many :holds, dependent: :restrict_with_error
  has_many :bookings, dependent: :restrict_with_error

  enum :bus_type, { ac_seater: 0, ac_sleeper: 1, non_ac_seater: 2, non_ac_sleeper: 3 }

  validates :from_city, :to_city, :travel_date, :departure_time, :arrival_time, presence: true
  validates :price, numericality: { greater_than: 0 }
  validates :total_seats, numericality: { only_integer: true, greater_than: 0 }
  validate :arrival_after_departure

  scope :for_route, ->(from_city, to_city) {
    where("lower(from_city) = ?", from_city.to_s.strip.downcase)
      .where("lower(to_city) = ?", to_city.to_s.strip.downcase)
  }
  scope :on_date, ->(date) { where(travel_date: date) }
  scope :min_operator_rating, ->(rating) { joins(:operator).where("operators.rating >= ?", rating) }
  scope :price_between, ->(min, max) { where(price: min..max) }
  scope :with_bus_type, ->(bus_type) { where(bus_type: bus_type) }
  # Postgres array containment (@>): trip.amenities must include every
  # requested amenity, e.g. amenities @> ARRAY['wifi','charging'].
  scope :with_amenities, ->(amenities) { where("amenities @> ARRAY[?]::varchar[]", Array(amenities)) }

  # Live count, never cached — see TripSearchService / IMPLEMENTATION_NOTES.md
  # for why seat availability must always be read fresh.
  def available_seats_count
    seats.available.count
  end

  private

  def arrival_after_departure
    return if arrival_time.blank? || departure_time.blank?
    errors.add(:arrival_time, "must be after departure time") if arrival_time <= departure_time
  end
end
