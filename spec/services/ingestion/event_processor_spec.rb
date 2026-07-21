require "rails_helper"

RSpec.describe Ingestion::EventProcessor do
  let(:valid_event) do
    {
      id: "evt_1",
      type: "PushEvent",
      actor: { id: 1, login: "octocat" },
      repo: { id: 100, name: "repo" },
      payload: {
        push_id: 123,
        ref: "refs/heads/main",
        head: "abc123",
        before: "def456"
      },
      created_at: "2026-07-20T12:00:00Z"
    }
  end

  describe "#process" do
    it "inserts a new event" do
      processor = described_class.new(valid_event)
      processor.process

      expect(processor.inserted?).to be true
      expect(PushEvent.find_by(github_event_id: "evt_1")).to be_present
    end

    it "stores raw JSON verbatim" do
      processor = described_class.new(valid_event)
      processor.process

      event = PushEvent.find_by(github_event_id: "evt_1")
      expect(event.raw_json).to include(
        type: "PushEvent",
        payload: include(push_id: 123)
      )
    end

    it "detects duplicate by github_event_id" do
      processor1 = described_class.new(valid_event)
      processor1.process

      processor2 = described_class.new(valid_event)
      processor2.process

      expect(processor2.duplicate?).to be true
      expect(PushEvent.where(github_event_id: "evt_1").count).to eq(1)
    end

    it "detects duplicate by push_id" do
      event1 = valid_event
      event2 = valid_event.merge(id: "evt_2")

      processor1 = described_class.new(event1)
      processor1.process

      processor2 = described_class.new(event2)
      processor2.process

      expect(processor2.duplicate?).to be true
    end

    it "marks malformed event without push_id" do
      malformed = valid_event.merge(payload: { ref: "refs/heads/main" })
      processor = described_class.new(malformed)
      processor.process

      expect(processor.malformed?).to be true
      expect(processor.error_message).to match(/push_id/)
      expect(PushEvent.count).to eq(0)
    end

    it "marks malformed event without payload" do
      malformed = valid_event.merge(payload: nil)
      processor = described_class.new(malformed)
      processor.process

      expect(processor.malformed?).to be true
      expect(PushEvent.count).to eq(0)
    end

    it "does not write raw_events, which the runner records for every event type" do
      processor = described_class.new(valid_event)
      processor.process

      expect(PushEvent.find_by(github_event_id: "evt_1")).to be_present
      expect(RawEvent.find_by(event_id: "evt_1")).to be_nil
    end

    it "idempotently stores duplicate events (no error)" do
      processor = described_class.new(valid_event)
      processor.process
      processor.process
      processor.process

      expect(PushEvent.where(github_event_id: "evt_1").count).to eq(1)
    end
  end

  describe "transaction isolation" do
    it "does not roll back other events if one event is malformed" do
      valid = valid_event
      malformed = valid.merge(id: "evt_malformed", payload: {})

      processor1 = described_class.new(valid)
      processor1.process

      processor2 = described_class.new(malformed)
      processor2.process

      expect(processor1.inserted?).to be true
      expect(processor2.malformed?).to be true
      expect(PushEvent.count).to eq(1)
    end
  end
end
