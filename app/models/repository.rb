# frozen_string_literal: true

class Repository < ApplicationRecord
  has_many :push_events, foreign_key: :repo_id, inverse_of: :repository, dependent: nil

  validates :id, presence: true
  validates :raw_json, presence: true

  def raw_json
    value = super
    value.is_a?(Hash) ? value.with_indifferent_access : value
  end
end
