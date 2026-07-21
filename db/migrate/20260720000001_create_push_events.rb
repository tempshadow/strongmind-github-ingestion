class CreatePushEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :push_events do |t|
      t.string :github_event_id, null: false
      t.bigint :push_id, null: false
      t.bigint :repo_id
      t.bigint :actor_id
      t.string :ref
      t.string :head_sha
      t.string :before_sha
      t.timestamptz :event_created_at
      t.jsonb :raw_json, null: false

      t.timestamps
    end

    add_index :push_events, :github_event_id, unique: true
    add_index :push_events, :push_id, unique: true
    add_index :push_events, :repo_id
    add_index :push_events, :actor_id
    add_index :push_events, :event_created_at
  end
end
