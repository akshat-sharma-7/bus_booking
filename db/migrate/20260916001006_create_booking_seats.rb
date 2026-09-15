class CreateBookingSeats < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_seats do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :seat, null: false, foreign_key: true
      # Snapshot of the seat's price at booking time, independent of Trip#price
      # potentially changing later — keeps historical bookings accurate.
      t.decimal :price, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :booking_seats, [:booking_id, :seat_id], unique: true
  end
end
