# User-initiated release, called when someone clicks "Cancel Hold" instead of
# waiting out the 5-minute timer or confirming. Deliberately does NOT go
# through HoldExpiryJob/HoldExpiryService — this needs to happen synchronously,
# in the same request, not on Sidekiq's schedule.
class CancelHoldService
  Result = Struct.new(:success?, :error, keyword_init: true)

  class Failure < StandardError; end

  def initialize(user:, hold_group_id:)
    @user = user
    @hold_group_id = hold_group_id
  end

  def call
    ActiveRecord::Base.transaction do
      # Scoped by user as well as hold_group_id — mirrors
      # BookingConfirmationService's ownership check: a hold_group_id that
      # exists but belongs to someone else returns the same "not found" as
      # one that doesn't exist at all, rather than leaking which is true.
      holds = Hold.where(hold_group_id: hold_group_id, user: user).order(:id).lock.to_a

      raise Failure, "Hold not found" if holds.empty?

      # Idempotent, not an error: if every hold in this group is already
      # confirmed, expired, or previously released, there's nothing left to
      # do — cancelling twice (or cancelling after it already expired, or
      # after it was already turned into a booking) must never corrupt that
      # state. Only holds still "active" get touched.
      holds.select(&:active?).each { |hold| HoldRelease.call(hold, status: :released) }
    end

    success
  rescue Failure => e
    failure(e.message)
  end

  private

  attr_reader :user, :hold_group_id

  def success = Result.new(success?: true)
  def failure(message) = Result.new(success?: false, error: message)
end
