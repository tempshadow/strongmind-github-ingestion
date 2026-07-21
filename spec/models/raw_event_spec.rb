require "rails_helper"

RSpec.describe RawEvent do
  describe "validations" do
    it "requires event_id" do
      event = described_class.new(payload: {})
      expect(event).not_to be_valid
      expect(event.errors[:event_id]).to be_present
    end

    it "requires payload" do
      event = described_class.new(event_id: "evt_1")
      expect(event).not_to be_valid
      expect(event.errors[:payload]).to be_present
    end
  end

  describe "uniqueness" do
    it "enforces unique event_id" do
      described_class.create!(
        event_id: "evt_1",
        payload: { type: "PushEvent" }
      )

      duplicate = described_class.new(
        event_id: "evt_1",
        payload: { type: "IssuesEvent" }
      )

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
