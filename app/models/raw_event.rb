class RawEvent < ApplicationRecord
  validates :event_id, presence: true, uniqueness: true
  validates :payload, presence: true
end
