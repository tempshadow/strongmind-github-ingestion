class CreatePushEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :push_events do |t|
      t.string :github_event_id, null: false
      t.bigint :push_id, null: false
      t.timestamptz :event_created_at
      t.jsonb :raw_json, null: false

      t.timestamps
    end

    add_index :push_events, :github_event_id, unique: true
    add_index :push_events, :push_id, unique: true
    add_index :push_events, :event_created_at
  end
end
