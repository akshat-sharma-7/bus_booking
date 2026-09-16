FactoryBot.define do
  factory :operator do
    sequence(:name) { |n| "Operator #{n}" }
    rating { 4.0 }
  end
end
