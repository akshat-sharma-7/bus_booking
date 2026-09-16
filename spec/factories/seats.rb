FactoryBot.define do
  factory :seat do
    trip
    sequence(:seat_number) { |n| "Z#{n}" }
    status { :available }
  end
end
