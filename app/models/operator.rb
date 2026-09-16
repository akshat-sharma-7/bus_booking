class Operator < ApplicationRecord
  has_many :trips, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
end
