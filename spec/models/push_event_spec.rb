require "rails_helper"

RSpec.describe PushEvent do
  describe "validations" do
    it "requires github_event_id" do
      event = described_class.new(push_id: 123, raw_json: {})
      expect(event).not_to be_valid
      expect(event.errors[:github_event_id]).to be_present
    end

    it "requires push_id" do
      event = described_class.new(github_event_id: "evt_1", raw_json: {})
      expect(event).not_to be_valid
      expect(event.errors[:push_id]).to be_present
    end

    it "requires raw_json" do
      event = described_class.new(github_event_id: "evt_1", push_id: 123)
      expect(event).not_to be_valid
      expect(event.errors[:raw_json]).to be_present
    end
  end

  describe "uniqueness" do
    it "enforces unique github_event_id" do
      described_class.create!(
        github_event_id: "evt_1",
        push_id: 123,
        raw_json: { type: "PushEvent" }
      )

      duplicate = described_class.new(
        github_event_id: "evt_1",
        push_id: 456,
        raw_json: { type: "PushEvent" }
      )

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces unique push_id" do
      described_class.create!(
        github_event_id: "evt_1",
        push_id: 123,
        raw_json: { type: "PushEvent" }
      )

      duplicate = described_class.new(
        github_event_id: "evt_2",
        push_id: 123,
        raw_json: { type: "PushEvent" }
      )

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
