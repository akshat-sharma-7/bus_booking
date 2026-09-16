class Booking < ApplicationRecord
  belongs_to :user
  belongs_to :trip
  has_many :booking_seats, dependent: :destroy
  has_many :seats, through: :booking_seats

  enum :status, { confirmed: 0, cancelled: 1, rescheduled: 2 }

  validates :hold_group_id, presence: true, uniqueness: true
  validates :total_price, numericality: { greater_than: 0 }
  validates :pnr, presence: true, uniqueness: true

  before_validation :generate_pnr, on: :create

  private

  # Passenger-facing reference only — NOT the idempotency mechanism (the
  # unique index on hold_group_id is). A collision here just means picking
  # a new random code, not a failed booking.
  def generate_pnr
    return if pnr.present?

    loop do
      candidate = "BK#{SecureRandom.alphanumeric(6).upcase}"
      unless Booking.exists?(pnr: candidate)
        self.pnr = candidate
        break
      end
    end
  end
end
