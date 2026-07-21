class PushEvent < ApplicationRecord
  # Optional: an event is persisted before enrichment runs, and enrichment may be
  # skipped when the rate-limit budget is short.
  belongs_to :actor, inverse_of: :push_events, optional: true
  belongs_to :repository, foreign_key: :repo_id, inverse_of: :push_events, optional: true

  validates :github_event_id, presence: true
  validates :push_id, presence: true
  validates :raw_json, presence: true

  # Uniqueness is enforced by the database so duplicates surface as RecordNotUnique.
  def raw_json
    value = super
    value.is_a?(Hash) ? value.with_indifferent_access : value
  end
end
