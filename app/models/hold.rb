class Hold < ApplicationRecord
  belongs_to :user
  belongs_to :trip
  belongs_to :seat

  enum :status, { active: 0, confirmed: 1, expired: 2, released: 3 }

  validates :hold_group_id, presence: true
  validates :expires_at, presence: true

  scope :still_active, -> { active.where("expires_at > ?", Time.current) }

  def expired_by_time?
    expires_at <= Time.current
  end
end
