class AddStructuredColumnsToPushEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :push_events, :repo_id, :bigint
    add_column :push_events, :actor_id, :bigint
    add_column :push_events, :ref, :string
    add_column :push_events, :head_sha, :string
    add_column :push_events, :before_sha, :string

    add_index :push_events, :repo_id
    add_index :push_events, :actor_id
  end
end
