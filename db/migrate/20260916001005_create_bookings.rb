class CreateBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :bookings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :trip, null: false, foreign_key: true

      t.uuid :hold_group_id, null: false
      # confirmed: 0, cancelled: 1, rescheduled: 2 (see Booking model enum) —
      # cancel/reschedule land in a later milestone; the enum just avoids a
      # future migration to widen this column.
      t.integer :status, null: false, default: 0
      t.decimal :total_price, precision: 10, scale: 2, null: false
      # Passenger-facing booking reference, e.g. "BK7F3K9A" — cosmetic, not a
      # concurrency/idempotency mechanism (hold_group_id is).
      t.string :pnr, null: false

      t.timestamps
    end

    # The actual idempotency guarantee for booking confirmation: two requests
    # racing to confirm the same hold group can only ever produce one row.
    add_index :bookings, :hold_group_id, unique: true
    add_index :bookings, :pnr, unique: true
  end
end
