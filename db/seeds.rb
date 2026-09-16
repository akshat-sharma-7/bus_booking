# Idempotent: safe to run `rails db:seed` repeatedly. Only touches domain
# tables (Operator/Trip/Seat/Hold/Booking/BookingSeat) — never touches Users,
# so real accounts created via signup survive a reseed.
puts "Clearing existing trip/booking data..."
BookingSeat.delete_all
Booking.delete_all
Hold.delete_all
Seat.delete_all
Trip.delete_all
Operator.delete_all

srand(2024) # deterministic-ish output across reseeds, for easier demoing

OPERATORS = [
  { name: "Shivneri Travels",  rating: 4.6 },
  { name: "VRL Travels",       rating: 4.1 },
  { name: "Orange Tours",      rating: 4.8 },
  { name: "SRS Travels",       rating: 3.7 },
  { name: "Patel Travels",     rating: 3.4 },
  { name: "Neeta Volvo",       rating: 4.3 },
  { name: "Sharma Travels",    rating: 4.4 },
  { name: "Om Travels",        rating: 3.9 }
].map { |attrs| Operator.create!(attrs) }
OPERATORS_BY_NAME = OPERATORS.index_by(&:name)

# Matches the "Popular Cities" dropdown in the search UI (TripsController)
# plus the existing route cities — every POPULAR_CITY appears in at least
# one route below.
ROUTES = [
  %w[Pune Mumbai],
  %w[Mumbai Pune],
  %w[Bangalore Chennai],
  %w[Chennai Bangalore],
  %w[Delhi Jaipur],
  %w[Jaipur Delhi],
  %w[Hyderabad Goa],
  %w[Goa Hyderabad],
  %w[Indore Bhopal],
  %w[Bhopal Indore],
  %w[Indore Dewas],
  %w[Dewas Indore],
  %w[Ahmedabad Mumbai],
  %w[Mumbai Ahmedabad],
  %w[Delhi Bhopal],
  %w[Bhopal Delhi]
]

AMENITY_POOL = Trip::AMENITY_OPTIONS
BUS_TYPES = Trip.bus_types.keys
SEAT_ROWS = 8
SEATS_PER_ROW = 4 # simple 2+2 layout for every bus_type — good enough for this assignment
TOTAL_SEATS = SEAT_ROWS * SEATS_PER_ROW

def seat_numbers(count)
  ("A".."Z").first(SEAT_ROWS).flat_map { |row| (1..SEATS_PER_ROW).map { |n| "#{row}#{n}" } }.first(count)
end

puts "Creating trips..."
trip_count = 0

ROUTES.each do |from_city, to_city|
  (1..5).each do |days_from_now|
    # 2 trips per route per day, at distinct hours so two trips never collide
    # on the (operator, route, departure_time) unique index even if the same
    # operator gets sampled twice for the same route/day.
    [6, 9, 14, 18, 22].sample(2).each do |departure_hour|
      operator = OPERATORS.sample
      travel_date = Date.current + days_from_now
      # Time.zone.local (not Date#to_time, which uses the system zone rather
      # than Rails' configured Time.zone) so the stored hour matches what we
      # picked once ActiveRecord reads it back in the app's time zone.
      departure_time = Time.zone.local(travel_date.year, travel_date.month, travel_date.day, departure_hour)
      duration_hours = rand(3..8)
      arrival_time = departure_time + duration_hours.hours

      bus_type = BUS_TYPES.sample
      base_price = bus_type.include?("sleeper") ? rand(700..1800) : rand(300..1200)
      amenities = AMENITY_POOL.sample(rand(1..AMENITY_POOL.size))

      trip = Trip.create!(
        operator: operator,
        from_city: from_city,
        to_city: to_city,
        travel_date: travel_date,
        departure_time: departure_time,
        arrival_time: arrival_time,
        price: base_price,
        bus_type: bus_type,
        amenities: amenities,
        total_seats: TOTAL_SEATS
      )

      seat_numbers(TOTAL_SEATS).each { |number| trip.seats.create!(seat_number: number) }

      # A handful of seats pre-booked so the seat map/search demo shows a
      # realistic mix of available/booked states, not an all-empty bus.
      trip.seats.sample(rand(0..6)).each { |seat| seat.update!(status: :booked) }

      trip_count += 1
    end
  end
end

puts "Creating repeated fixed schedules (same operator/route/bus, multiple dates)..."

# Each entry is one recurring schedule: same operator, route, bus_type and
# price, run every other day. Each departure is still its own Trip row (this
# app's Trip directly represents one scheduled departure — there's no
# separate Bus model to reuse across dates, so "recurring" just means
# creating several Trips that happen to share everything but the date).
RECURRING_SCHEDULES = [
  { operator: "Sharma Travels", from_city: "Indore", to_city: "Ujjain", hour: 8,
    bus_type: :ac_sleeper, price: 450, amenities: %w[wifi charging blanket] },
  { operator: "Om Travels", from_city: "Bhopal", to_city: "Indore", hour: 14,
    bus_type: :non_ac_seater, price: 280, amenities: %w[charging] }
]

RECURRING_SCHEDULES.each do |schedule|
  operator = OPERATORS_BY_NAME.fetch(schedule[:operator])

  [0, 2, 4, 6, 8].each do |days_from_now|
    travel_date = Date.current + days_from_now
    departure_time = Time.zone.local(travel_date.year, travel_date.month, travel_date.day, schedule[:hour])

    trip = Trip.create!(
      operator: operator,
      from_city: schedule[:from_city],
      to_city: schedule[:to_city],
      travel_date: travel_date,
      departure_time: departure_time,
      arrival_time: departure_time + 3.hours,
      price: schedule[:price],
      bus_type: schedule[:bus_type],
      amenities: schedule[:amenities],
      total_seats: TOTAL_SEATS
    )

    seat_numbers(TOTAL_SEATS).each { |number| trip.seats.create!(seat_number: number) }
    trip.seats.sample(rand(0..4)).each { |seat| seat.update!(status: :booked) }

    trip_count += 1
  end
end

puts "Seeded #{OPERATORS.size} operators, #{trip_count} trips, #{Seat.count} seats."
