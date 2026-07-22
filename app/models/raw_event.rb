# frozen_string_literal: true

class RawEvent < ApplicationRecord
  validates :event_id, presence: true
  validates :payload, presence: true

  # Uniqueness is enforced by the database so duplicates surface as RecordNotUnique.
  def payload
    value = super
    value.is_a?(Hash) ? value.with_indifferent_access : value
  end
end
