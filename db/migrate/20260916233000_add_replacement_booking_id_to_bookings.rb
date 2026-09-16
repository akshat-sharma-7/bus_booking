class AddReplacementBookingIdToBookings < ActiveRecord::Migration[8.0]
  def change
    # Traceability only — NOT the reschedule idempotency mechanism (that's the
    # pessimistic lock + status check on the original booking row itself; see
    # RescheduleBookingService / IMPLEMENTATION_NOTES.md "Reschedule
    # architecture"). Nullable: only set on a booking once it's been
    # rescheduled, always pointing forward to its one replacement.
    add_reference :bookings, :replacement_booking, foreign_key: { to_table: :bookings }, null: true
  end
end
