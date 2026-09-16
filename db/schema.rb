# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_09_16_233000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "booking_seats", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "seat_id", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id", "seat_id"], name: "index_booking_seats_on_booking_id_and_seat_id", unique: true
    t.index ["booking_id"], name: "index_booking_seats_on_booking_id"
    t.index ["seat_id"], name: "index_booking_seats_on_seat_id"
  end

  create_table "bookings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "trip_id", null: false
    t.uuid "hold_group_id", null: false
    t.integer "status", default: 0, null: false
    t.decimal "total_price", precision: 10, scale: 2, null: false
    t.string "pnr", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "replacement_booking_id"
    t.index ["hold_group_id"], name: "index_bookings_on_hold_group_id", unique: true
    t.index ["pnr"], name: "index_bookings_on_pnr", unique: true
    t.index ["replacement_booking_id"], name: "index_bookings_on_replacement_booking_id"
    t.index ["trip_id"], name: "index_bookings_on_trip_id"
    t.index ["user_id"], name: "index_bookings_on_user_id"
  end

  create_table "holds", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "trip_id", null: false
    t.bigint "seat_id", null: false
    t.uuid "hold_group_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_holds_on_expires_at"
    t.index ["hold_group_id"], name: "index_holds_on_hold_group_id"
    t.index ["seat_id"], name: "index_holds_on_seat_id"
    t.index ["seat_id"], name: "index_holds_on_seat_id_when_active", unique: true, where: "(status = 0)"
    t.index ["trip_id"], name: "index_holds_on_trip_id"
    t.index ["user_id"], name: "index_holds_on_user_id"
  end

  create_table "operators", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "rating", precision: 3, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_operators_on_name", unique: true
    t.index ["rating"], name: "index_operators_on_rating"
  end

  create_table "seats", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.string "seat_number", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trip_id", "seat_number"], name: "index_seats_on_trip_id_and_seat_number", unique: true
    t.index ["trip_id", "status"], name: "index_seats_on_trip_id_and_status"
    t.index ["trip_id"], name: "index_seats_on_trip_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "trips", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "from_city", null: false
    t.string "to_city", null: false
    t.date "travel_date", null: false
    t.datetime "departure_time", null: false
    t.datetime "arrival_time", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.integer "bus_type", default: 0, null: false
    t.string "amenities", default: [], null: false, array: true
    t.integer "total_seats", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["amenities"], name: "index_trips_on_amenities", using: :gin
    t.index ["from_city", "to_city", "travel_date"], name: "index_trips_on_from_city_and_to_city_and_travel_date"
    t.index ["operator_id", "from_city", "to_city", "departure_time"], name: "index_trips_on_operator_route_departure", unique: true
    t.index ["operator_id"], name: "index_trips_on_operator_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "booking_seats", "bookings"
  add_foreign_key "booking_seats", "seats"
  add_foreign_key "bookings", "bookings", column: "replacement_booking_id"
  add_foreign_key "bookings", "trips"
  add_foreign_key "bookings", "users"
  add_foreign_key "holds", "seats"
  add_foreign_key "holds", "trips"
  add_foreign_key "holds", "users"
  add_foreign_key "seats", "trips"
  add_foreign_key "sessions", "users"
  add_foreign_key "trips", "operators"
end
