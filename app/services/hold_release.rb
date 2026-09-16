# Shared by HoldExpiryService (timer-based) and CancelHoldService
# (user-initiated) — both ultimately do the same two things to a Hold that's
# no longer active: stamp its terminal status and free its seat. Caller is
# responsible for locking the hold (and running inside a transaction) before
# calling this — it does not lock on its own.
module HoldRelease
  module_function

  def call(hold, status:)
    hold.update!(status: status)
    seat = hold.seat.lock!
    seat.update!(status: :available) if seat.held?
  end
end
