class CreateActors < ActiveRecord::Migration[7.1]
  def change
    # GitHub's actor ID is the primary key, so a cache lookup is a primary-key hit.
    create_table :actors, id: false do |t|
      t.bigint :id, primary_key: true, default: nil
      t.string :login
      t.string :url
      t.string :avatar_url
      t.jsonb :raw_json, null: false
      t.timestamptz :fetched_at

      t.timestamps
    end

    add_index :actors, :login
  end
end
