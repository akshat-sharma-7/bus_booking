class CreateHolds < ActiveRecord::Migration[8.0]
  def change
    create_table :holds do |t|
      t.references :user, null: false, foreign_key: true
      t.references :trip, null: false, foreign_key: true
      t.references :seat, null: false, foreign_key: true

      # Groups the N holds created by one seat-selection request (one per seat)
      # so they can be looked up and confirmed into a single Booking together.
      t.uuid :hold_group_id, null: false

      # active: 0, confirmed: 1, expired: 2, released: 3 (see Hold model enum)
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :holds, :hold_group_id
    add_index :holds, :expires_at

    # The actual concurrency guarantee: Postgres physically refuses a second
    # active hold on the same seat, independent of whatever locking the
    # application does. status = 0 is "active" — see Hold model enum.
    add_index :holds, :seat_id, unique: true, where: "status = 0",
               name: "index_holds_on_seat_id_when_active"
  end
end
