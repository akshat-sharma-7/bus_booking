FactoryBot.define do
  factory :trip do
    operator
    from_city { "Pune" }
    to_city { "Mumbai" }
    travel_date { 1.day.from_now.to_date }
    departure_time { 1.day.from_now.change(hour: 9) }
    arrival_time { 1.day.from_now.change(hour: 13) }
    price { 500 }
    bus_type { :ac_seater }
    amenities { ["wifi"] }
    total_seats { 10 }

    transient do
      seats_count { 10 }
    end

    after(:create) do |trip, evaluator|
      evaluator.seats_count.times do |i|
        trip.seats.create!(seat_number: "A#{i + 1}")
      end
    end
  end
end
