class PushEvent < ApplicationRecord
  validates :github_event_id, presence: true
  validates :push_id, presence: true
  validates :raw_json, presence: true

  # Uniqueness is enforced by the database so duplicates surface as RecordNotUnique.
  def raw_json
    value = super
    value.is_a?(Hash) ? value.with_indifferent_access : value
  end
end
