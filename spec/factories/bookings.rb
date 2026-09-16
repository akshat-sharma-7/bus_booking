FactoryBot.define do
  factory :booking do
    user
    trip
    hold_group_id { SecureRandom.uuid }
    total_price { 500 }
  end
end
