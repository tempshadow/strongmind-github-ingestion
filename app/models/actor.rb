class Actor < ApplicationRecord
  self.primary_key = :id
  validates :raw_json, presence: true
end
