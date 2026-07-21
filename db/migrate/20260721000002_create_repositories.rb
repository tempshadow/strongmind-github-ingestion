class CreateRepositories < ActiveRecord::Migration[7.1]
  def change
    # GitHub's repository ID is the primary key, so a cache lookup is a primary-key hit.
    create_table :repositories, id: false do |t|
      t.bigint :id, primary_key: true, default: nil
      t.string :name
      t.string :full_name
      t.string :url
      t.jsonb :raw_json, null: false
      t.timestamptz :fetched_at

      t.timestamps
    end

    add_index :repositories, :full_name, unique: true
  end
end
