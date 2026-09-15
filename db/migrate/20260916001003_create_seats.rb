class CreateSeats < ActiveRecord::Migration[8.0]
  def change
    create_table :seats do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :seat_number, null: false
      # available: 0, held: 1, booked: 2 (see Seat model enum)
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :seats, [:trip_id, :seat_number], unique: true
    # Seat map rendering and availability counts both filter by (trip_id, status).
    add_index :seats, [:trip_id, :status]
  end
end
