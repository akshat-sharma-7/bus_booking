class BookingSeat < ApplicationRecord
  belongs_to :booking
  belongs_to :seat

  validates :price, numericality: { greater_than: 0 }
  validates :seat_id, uniqueness: { scope: :booking_id }
end
