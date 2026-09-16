class CreateOperators < ActiveRecord::Migration[8.0]
  def change
    create_table :operators do |t|
      t.string :name, null: false
      t.decimal :rating, precision: 3, scale: 2, null: false, default: 0.0

      t.timestamps
    end

    add_index :operators, :name, unique: true
    add_index :operators, :rating
  end
end
