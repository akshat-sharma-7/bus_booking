require "rails_helper"

RSpec.describe TripSearchService do
  let(:pune_mumbai_high_rated) do
    create(:trip, from_city: "Pune", to_city: "Mumbai", travel_date: Date.tomorrow,
                   price: 600, bus_type: :ac_seater, amenities: %w[wifi charging],
                   operator: create(:operator, rating: 4.8), seats_count: 2)
  end

  let(:pune_mumbai_low_rated) do
    create(:trip, from_city: "Pune", to_city: "Mumbai", travel_date: Date.tomorrow,
                   price: 300, bus_type: :non_ac_seater, amenities: [],
                   operator: create(:operator, rating: 3.0), seats_count: 2)
  end

  let(:other_route) do
    create(:trip, from_city: "Delhi", to_city: "Jaipur", travel_date: Date.tomorrow,
                   operator: create(:operator, rating: 4.5), seats_count: 2)
  end

  before do
    pune_mumbai_high_rated
    pune_mumbai_low_rated
    other_route
  end

  def trips_in(results) = results.map(&:trip)

  it "filters by route and date" do
    results = described_class.new(from_city: "Pune", to_city: "Mumbai", travel_date: Date.tomorrow.iso8601).call

    expect(trips_in(results)).to contain_exactly(pune_mumbai_high_rated, pune_mumbai_low_rated)
  end

  it "filters by minimum operator rating" do
    results = described_class.new(from_city: "Pune", to_city: "Mumbai", min_rating: "4.0").call

    expect(trips_in(results)).to contain_exactly(pune_mumbai_high_rated)
  end

  it "filters by price range" do
    results = described_class.new(from_city: "Pune", to_city: "Mumbai", price_min: "500", price_max: "700").call

    expect(trips_in(results)).to contain_exactly(pune_mumbai_high_rated)
  end

  it "filters by bus type" do
    results = described_class.new(from_city: "Pune", to_city: "Mumbai", bus_type: "non_ac_seater").call

    expect(trips_in(results)).to contain_exactly(pune_mumbai_low_rated)
  end

  it "filters by amenities (must include all requested)" do
    results = described_class.new(from_city: "Pune", to_city: "Mumbai", amenities: %w[wifi charging]).call

    expect(trips_in(results)).to contain_exactly(pune_mumbai_high_rated)
  end

  it "returns the live available-seat count, not a cached one" do
    pune_mumbai_high_rated.seats.first.update!(status: :booked)

    results = described_class.new(from_city: "Pune", to_city: "Mumbai").call
    result = results.find { |r| r.trip == pune_mumbai_high_rated }

    expect(result.available_seats_count).to eq(1)
  end

  it "returns today's trips when searching for today's date" do
    today_trip = create(:trip, from_city: "Pune", to_city: "Mumbai", travel_date: Date.current)

    results = described_class.new(from_city: "Pune", to_city: "Mumbai", travel_date: Date.current.iso8601).call

    expect(trips_in(results)).to contain_exactly(today_trip)
  end

  it "returns tomorrow's trips when searching for tomorrow's date" do
    results = described_class.new(from_city: "Pune", to_city: "Mumbai", travel_date: Date.tomorrow.iso8601).call

    expect(trips_in(results)).to contain_exactly(pune_mumbai_high_rated, pune_mumbai_low_rated)
  end

  it "returns trips for an arbitrary requested date, excluding other dates" do
    later_trip = create(:trip, from_city: "Pune", to_city: "Mumbai", travel_date: 5.days.from_now.to_date)

    results = described_class.new(from_city: "Pune", to_city: "Mumbai", travel_date: 5.days.from_now.to_date.iso8601).call

    expect(trips_in(results)).to contain_exactly(later_trip)
  end

  it "finds every date of a recurring schedule (same operator/route/bus_type, several dates)" do
    operator = create(:operator, name: "Sharma Travels", rating: 4.4)
    recurring_dates = [Date.current, Date.current + 2, Date.current + 4]
    recurring_trips = recurring_dates.map do |date|
      create(:trip, operator: operator, from_city: "Indore", to_city: "Ujjain", travel_date: date,
                     departure_time: date.to_time.change(hour: 8), arrival_time: date.to_time.change(hour: 11),
                     bus_type: :ac_sleeper)
    end

    recurring_dates.each do |date|
      results = described_class.new(from_city: "Indore", to_city: "Ujjain", travel_date: date.iso8601).call
      expect(trips_in(results)).to contain_exactly(recurring_trips[recurring_dates.index(date)])
    end
  end

  it "never serves a stale seat count from cache, even when the trip list itself is cached" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    params = { from_city: "Pune", to_city: "Mumbai" }

    first = described_class.new(params).call.find { |r| r.trip == pune_mumbai_high_rated }
    expect(first.available_seats_count).to eq(2)

    # Trip metadata list is now cached — confirm a second identical call
    # really does hit the cache (proves the caching behavior is real)...
    trip_ids_key = described_class.new(params).send(:cache_key)
    expect(Rails.cache.exist?(trip_ids_key)).to be true

    # ...but the availability number still reflects a change made after that
    # cache was populated, because it's never part of what's cached.
    pune_mumbai_high_rated.seats.first.update!(status: :booked)
    second = described_class.new(params).call.find { |r| r.trip == pune_mumbai_high_rated }
    expect(second.available_seats_count).to eq(1)
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end
end
