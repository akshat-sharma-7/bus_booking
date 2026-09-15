# Idempotent and safe to run more than once (Sidekiq/ActiveJob's at-least-once
# delivery can redeliver): HoldExpiryService's `where(status: "active")` scope
# means a hold already confirmed, cancelled, or expired by a previous run is
# simply skipped.
class HoldExpiryJob < ApplicationJob
  queue_as :default

  def perform(hold_group_id)
    HoldExpiryService.new(hold_group_id: hold_group_id).call
  end
end
