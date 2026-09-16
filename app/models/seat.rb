class Seat < ApplicationRecord
  belongs_to :trip
  has_many :holds, dependent: :restrict_with_error
  has_many :booking_seats, dependent: :restrict_with_error

  enum :status, { available: 0, held: 1, booked: 2 }

  validates :seat_number, presence: true, uniqueness: { scope: :trip_id }
end
