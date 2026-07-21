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

ActiveRecord::Schema[7.1].define(version: 2026_07_20_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "push_events", force: :cascade do |t|
    t.string "github_event_id", null: false
    t.bigint "push_id", null: false
    t.timestamptz "event_created_at"
    t.jsonb "raw_json", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "repo_id"
    t.bigint "actor_id"
    t.string "ref"
    t.string "head_sha"
    t.string "before_sha"
    t.index ["actor_id"], name: "index_push_events_on_actor_id"
    t.index ["event_created_at"], name: "index_push_events_on_event_created_at"
    t.index ["github_event_id"], name: "index_push_events_on_github_event_id", unique: true
    t.index ["push_id"], name: "index_push_events_on_push_id", unique: true
    t.index ["repo_id"], name: "index_push_events_on_repo_id"
  end

  create_table "raw_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.jsonb "payload", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_raw_events_on_event_id", unique: true
  end

end
