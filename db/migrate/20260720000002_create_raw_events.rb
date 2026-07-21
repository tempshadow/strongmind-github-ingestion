class CreateRawEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :raw_events do |t|
      t.string :event_id, null: false
      t.jsonb :payload, null: false

      t.timestamps
    end

    add_index :raw_events, :event_id, unique: true
  end
end
