require "rails_helper"

RSpec.describe Ingestion::EventFilter do
  describe "#filter" do
    it "filters to PushEvent only" do
      events = [
        { type: "PushEvent", id: "1" },
        { type: "PushEvent", id: "2" },
        { type: "IssuesEvent", id: "3" },
        { type: "PullRequestEvent", id: "4" }
      ]

      filter = described_class.new(events).filter
      expect(filter.push_events.length).to eq(2)
      expect(filter.rejected_count).to eq(2)
    end

    it "returns empty array when no PushEvents" do
      events = [
        { type: "IssuesEvent", id: "1" },
        { type: "PullRequestEvent", id: "2" }
      ]

      filter = described_class.new(events).filter
      expect(filter.push_events).to be_empty
      expect(filter.rejected_count).to eq(2)
    end

    it "counts rejected events correctly" do
      events = [
        { type: "PushEvent", id: "1" },
        { type: "WatchEvent", id: "2" },
        { type: "PushEvent", id: "3" },
        { type: "ForkEvent", id: "4" },
        { type: "PushEvent", id: "5" }
      ]

      filter = described_class.new(events).filter
      expect(filter.push_events.length).to eq(3)
      expect(filter.rejected_count).to eq(2)
    end
  end
end
