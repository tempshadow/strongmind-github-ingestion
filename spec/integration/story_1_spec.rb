require "rails_helper"

RSpec.describe "Story 1: Ingest GitHub Push Events" do
  let(:mock_client) { instance_double(Github::Client) }
  let(:runner) { Ingestion::Runner.new(client: mock_client) }

  let(:github_events) do
    [
      {
        id: "26670d9da60f88c8ec86b1c79e5c00d8ffc9883b",
        type: "PushEvent",
        actor: {
          id: 1,
          login: "octocat",
          url: "https://api.github.com/users/octocat"
        },
        repo: {
          id: 1296269,
          name: "Hello-World",
          url: "https://api.github.com/repos/octocat/Hello-World"
        },
        payload: {
          push_id: 1,
          ref: "refs/heads/main",
          head: "0d1a26e67d8f5eaf100f6b73408ac5e3e8fab507",
          before: "6dcb09b5b57875f334f61aebed695e2e4193db5e"
        },
        created_at: "2026-07-20T12:00:00Z"
      },
      {
        id: "26670d9da60f88c8ec86b1c79e5c00d8ffc9883c",
        type: "PushEvent",
        actor: {
          id: 2,
          login: "hubot",
          url: "https://api.github.com/users/hubot"
        },
        repo: {
          id: 1296270,
          name: "Spoon-Knife",
          url: "https://api.github.com/repos/octocat/Spoon-Knife"
        },
        payload: {
          push_id: 2,
          ref: "refs/heads/feature-branch",
          head: "1d1a26e67d8f5eaf100f6b73408ac5e3e8fab508",
          before: "7dcb09b5b57875f334f61aebed695e2e4193db5e"
        },
        created_at: "2026-07-20T12:01:00Z"
      },
      {
        id: "26670d9da60f88c8ec86b1c79e5c00d8ffc9883d",
        type: "IssuesEvent",
        actor: {
          id: 3,
          login: "other-user",
          url: "https://api.github.com/users/other-user"
        },
        repo: {
          id: 1296271,
          name: "Hello-World",
          url: "https://api.github.com/repos/octocat/Hello-World"
        },
        payload: {
          action: "opened",
          issue: { id: 1, title: "Found a bug" }
        },
        created_at: "2026-07-20T12:02:00Z"
      }
    ]
  end

  describe "run_once with fresh database" do
    it "ingests PushEvents and stores raw data durably" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: github_events,
      })

      summary = runner.run_once

      # Verify counts
      expect(summary.fetched_count).to eq(3)
      expect(summary.filtered_count).to eq(2)
      expect(summary.inserted_count).to eq(2)
      expect(summary.duplicate_count).to eq(0)
      expect(summary.malformed_count).to eq(0)

      # Verify push_events were stored
      expect(PushEvent.count).to eq(2)
      push1 = PushEvent.find_by(push_id: 1)
      push2 = PushEvent.find_by(push_id: 2)

      expect(push1).to be_present
      expect(push1.github_event_id).to eq("26670d9da60f88c8ec86b1c79e5c00d8ffc9883b")

      expect(push2).to be_present
      expect(push2.github_event_id).to eq("26670d9da60f88c8ec86b1c79e5c00d8ffc9883c")

      # Verify raw_events were stored (all event types)
      expect(RawEvent.count).to eq(3)
      raw_push1 = RawEvent.find_by(event_id: "26670d9da60f88c8ec86b1c79e5c00d8ffc9883b")
      raw_issue = RawEvent.find_by(event_id: "26670d9da60f88c8ec86b1c79e5c00d8ffc9883d")

      expect(raw_push1.payload[:type]).to eq("PushEvent")
      expect(raw_issue.payload[:type]).to eq("IssuesEvent")

      # Verify raw JSON is stored verbatim
      expect(push1.raw_json[:payload][:push_id]).to eq(1)
      expect(push1.raw_json[:actor][:login]).to eq("octocat")
    end
  end

  describe "idempotency" do
    it "skips duplicates on second run" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: github_events,
      })

      # First run
      summary1 = runner.run_once
      expect(summary1.inserted_count).to eq(2)
      expect(summary1.duplicate_count).to eq(0)
      expect(PushEvent.count).to eq(2)

      # Second run with same events
      summary2 = runner.run_once
      expect(summary2.inserted_count).to eq(0)
      expect(summary2.duplicate_count).to eq(2)
      expect(PushEvent.count).to eq(2)

      # Verify row counts haven't changed
      expect(RawEvent.count).to eq(3)
    end

    it "enforces uniqueness by github_event_id at database level" do
      event = {
        id: "test_evt_1",
        type: "PushEvent",
        actor: { id: 1 },
        repo: { id: 100 },
        payload: { push_id: 999, ref: "refs/heads/main", head: "abc", before: "def" },
        created_at: "2026-07-20T12:00:00Z"
      }

      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: [event],
      })

      runner.run_once
      runner.run_once
      runner.run_once

      expect(PushEvent.where(github_event_id: "test_evt_1").count).to eq(1)
    end

    it "enforces uniqueness by push_id at database level" do
      event1 = {
        id: "evt_a",
        type: "PushEvent",
        actor: { id: 1 },
        repo: { id: 100 },
        payload: { push_id: 777, ref: "refs/heads/main", head: "abc", before: "def" },
        created_at: "2026-07-20T12:00:00Z"
      }

      event2 = {
        id: "evt_b",
        type: "PushEvent",
        actor: { id: 2 },
        repo: { id: 101 },
        payload: { push_id: 777, ref: "refs/heads/main", head: "xyz", before: "uvw" },
        created_at: "2026-07-20T12:01:00Z"
      }

      # First event succeeds
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: [event1],
      })

      summary1 = runner.run_once
      expect(summary1.inserted_count).to eq(1)

      # Second event with same push_id fails uniqueness check
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: [event2],
      })

      summary2 = runner.run_once
      expect(summary2.duplicate_count).to eq(1)
      expect(PushEvent.count).to eq(1)
    end
  end

  describe "filtering non-PushEvents" do
    it "stores all event types in raw_events but only PushEvents in push_events" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: github_events,
      })

      runner.run_once

      # Push events only
      expect(PushEvent.count).to eq(2)
      expect(PushEvent.pluck(:push_id)).to contain_exactly(1, 2)

      # All events
      expect(RawEvent.count).to eq(3)
      expect(RawEvent.pluck(:event_id)).to contain_exactly(
        "26670d9da60f88c8ec86b1c79e5c00d8ffc9883b",
        "26670d9da60f88c8ec86b1c79e5c00d8ffc9883c",
        "26670d9da60f88c8ec86b1c79e5c00d8ffc9883d"
      )
    end
  end

  describe "empty feed response" do
    it "handles an empty feed gracefully" do
      allow(mock_client).to receive(:fetch_events).and_return({
        status: 200,
        body: [],
      })

      summary = runner.run_once

      expect(summary.fetched_count).to eq(0)
      expect(summary.filtered_count).to eq(0)
      expect(summary.inserted_count).to eq(0)
      expect(PushEvent.count).to eq(0)
    end
  end
end
