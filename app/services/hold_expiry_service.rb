# Time-based release, called from HoldExpiryJob. Only touches holds that are
# BOTH still "active" and actually past their expires_at — a hold already
# confirmed into a booking, already cancelled, or already expired by an
# earlier (possibly redelivered) run of this same job is left untouched.
class HoldExpiryService
  def initialize(hold_group_id:)
    @hold_group_id = hold_group_id
  end

  def call
    ActiveRecord::Base.transaction do
      holds = Hold.where(hold_group_id: hold_group_id, status: :active).order(:id).lock.to_a

      holds.each do |hold|
        next unless hold.expired_by_time?

        HoldRelease.call(hold, status: :expired)
      end
    end
  end

  private

  attr_reader :hold_group_id
end
