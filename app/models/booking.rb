class Booking < ApplicationRecord
  # Flat fee per booking (not per seat) deducted from a cancellation refund —
  # see CancellationService. No payment gateway exists in this app, so this
  # is a calculated figure only, never charged/settled anywhere.
  CANCELLATION_FEE = 50

  belongs_to :user
  belongs_to :trip
  has_many :booking_seats, dependent: :destroy
  has_many :seats, through: :booking_seats

  # Traceability only, set on the ORIGINAL booking once it's been
  # rescheduled — see RescheduleBookingService. Not the idempotency
  # mechanism (a pessimistic lock + status check on this row is).
  belongs_to :replacement_booking, class_name: "Booking", optional: true
  has_one :original_booking, class_name: "Booking", foreign_key: :replacement_booking_id, inverse_of: :replacement_booking

  enum :status, { confirmed: 0, cancelled: 1, rescheduled: 2 }

  validates :hold_group_id, presence: true, uniqueness: true
  validates :total_price, numericality: { greater_than: 0 }
  validates :pnr, presence: true, uniqueness: true

  before_validation :generate_pnr, on: :create

  # Computed on demand, not persisted — always consistent with total_price,
  # and there's nowhere in this app that actually settles a refund anyway.
  def refund_amount
    total_price - CANCELLATION_FEE
  end

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
