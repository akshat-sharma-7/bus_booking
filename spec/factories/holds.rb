FactoryBot.define do
  factory :hold do
    user
    trip
    seat
    hold_group_id { SecureRandom.uuid }
    status { :active }
    expires_at { 5.minutes.from_now }
  end
end
