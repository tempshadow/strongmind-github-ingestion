require "rails_helper"

RSpec.describe Ingestion::Runner do
  let(:mock_client) { instance_double(Github::Client) }
  let(:runner) { described_class.new(client: mock_client) }

  let(:events_response) do
    [
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
      },
      {
        id: "evt_2",
        type: "PushEvent",
        actor: { id: 2, login: "other" },
        repo: { id: 101, name: "repo2" },
        payload: {
          push_id: 124,
          ref: "refs/heads/develop",
          head: "xyz789",
          before: "uvw012"
        },
        created_at: "2026-07-20T12:01:00Z"
      },
      {
        id: "evt_3",
        type: "IssuesEvent",
        actor: { id: 3 },
        repo: { id: 102 },
        payload: { action: "opened" },
        created_at: "2026-07-20T12:02:00Z"
      }
    ]
  end
  describe "#run_once" do
    it "fetches events and persists them" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: events_response,
      })

      summary = runner.run_once

      expect(summary.fetched_count).to eq(3)
      expect(summary.filtered_count).to eq(2)
      expect(summary.inserted_count).to eq(2)
      expect(summary.malformed_count).to eq(0)
      expect(summary.duplicate_count).to eq(0)
    end

    it "handles empty response" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: [],
      })

      summary = runner.run_once

      expect(summary.fetched_count).to eq(0)
      expect(summary.filtered_count).to eq(0)
      expect(summary.inserted_count).to eq(0)
    end

    it "detects duplicates on second run" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: events_response,
      })

      summary1 = runner.run_once
      expect(summary1.inserted_count).to eq(2)

      summary2 = runner.run_once
      expect(summary2.inserted_count).to eq(0)
      expect(summary2.duplicate_count).to eq(2)
    end

    it "counts rejected non-PushEvents" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: events_response,
      })

      summary = runner.run_once

      expect(summary.filtered_count).to eq(2)
    end

    it "records a raw_event for every event type, not just PushEvents" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: events_response,
      })

      runner.run_once

      expect(RawEvent.count).to eq(events_response.length)
      expect(RawEvent.pluck(:event_id)).to match_array(events_response.map { |e| e[:id] })
    end
  end

  describe "error handling" do
    it "continues processing when one event is malformed" do
      malformed_response = events_response.dup
      malformed_response[0] = malformed_response[0].merge(payload: {})

      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: malformed_response,
      })

      summary = runner.run_once

      expect(summary.inserted_count).to eq(1)
      expect(summary.malformed_count).to eq(1)
    end
  end

  describe "enrichment" do
    let(:enrichable) do
      [
        events_response.first.deep_merge(
          actor: { url: "https://api.github.com/users/octocat" },
          repo: { url: "https://api.github.com/repos/octocat/Hello-World" }
        )
      ]
    end

    before do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: enrichable,
        rate_limit: Github::RateLimit.new(limit: 60, remaining: 50, reset: nil)
      })
      allow(mock_client).to receive(:fetch_resource).and_return({
        status: 200,
        body: { login: "octocat", full_name: "octocat/Hello-World" },
        rate_limit: Github::RateLimit.new(limit: 60, remaining: 48, reset: nil)
      })
    end

    it "reports enrichment counts and the latest rate-limit posture" do
      summary = runner.run_once

      expect(summary.enrichment_fetches).to eq(2)
      expect(summary.enrichment_hits).to eq(0)
      expect(summary.enrichment_skips).to eq(0)
      expect(summary.rate_limit.remaining).to eq(48)
    end

    it "reports cache hits on the second cycle" do
      runner.run_once
      summary = runner.run_once

      expect(summary.enrichment_hits).to eq(2)
      expect(summary.enrichment_fetches).to eq(0)
    end

    it "reports an unknown budget when the feed sends no headers" do
      allow(mock_client).to receive(:fetch_events).and_return({ status: 200, body: [] })

      expect(runner.run_once.rate_limit).not_to be_known
    end
  end

  describe "#run_once idempotency" do
    it "is safe to call multiple times with the same data" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: events_response,
      })

      3.times do
        runner.run_once
      end

      expect(PushEvent.count).to eq(2)
      expect(RawEvent.count).to eq(3)
    end
  end
end
