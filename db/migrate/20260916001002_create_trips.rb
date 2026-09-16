class CreateTrips < ActiveRecord::Migration[8.0]
  def change
    create_table :trips do |t|
      t.references :operator, null: false, foreign_key: true

      t.string :from_city, null: false
      t.string :to_city, null: false
      t.date :travel_date, null: false
      t.datetime :departure_time, null: false
      t.datetime :arrival_time, null: false

      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :bus_type, null: false, default: 0
      t.string :amenities, array: true, null: false, default: []
      t.integer :total_seats, null: false

      t.timestamps
    end

    add_index :trips, [:from_city, :to_city, :travel_date]

    # A given operator can't run two trips on the same route departing at the
    # same instant — the "appropriate uniqueness constraint" for a scheduled trip.
    add_index :trips, [:operator_id, :from_city, :to_city, :departure_time],
               unique: true, name: "index_trips_on_operator_route_departure"

    add_index :trips, :amenities, using: :gin
  end
end
