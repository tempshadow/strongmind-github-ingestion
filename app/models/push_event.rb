class PushEvent < ApplicationRecord
  validates :github_event_id, presence: true, uniqueness: true
  validates :push_id, presence: true, uniqueness: true
  validates :raw_json, presence: true
end
