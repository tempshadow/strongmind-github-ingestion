require "rails_helper"

RSpec.describe "Story 4: Operability and Observability" do
  let(:sink) { StringIO.new }
  let(:mock_client) { instance_double(Github::Client) }
  let(:runner) { Ingestion::Runner.new(client: mock_client, config: Ingestion.config) }

  let(:events) do
    [
      {
        id: "evt_1",
        type: "PushEvent",
        actor: { id: 1, login: "octocat", url: "https://api.github.com/users/octocat" },
        repo: { id: 100, name: "Hello-World", url: "https://api.github.com/repos/octocat/Hello-World" },
        payload: { push_id: 1, ref: "refs/heads/main", head: "abc", before: "def" },
        created_at: "2026-07-21T12:00:00Z"
      },
      { id: "evt_2", type: "IssuesEvent", actor: { id: 2 }, repo: { id: 101 },
        payload: { action: "opened" }, created_at: "2026-07-21T12:01:00Z" }
    ]
  end

  def healthy_response(body: events, remaining: "50")
    { status: 200, body: body,
      rate_limit: Github::RateLimit.new(limit: 60, remaining: remaining, reset: nil) }
  end

  before do
    allow(Rails).to receive(:logger).and_return(
      ActiveSupport::Logger.new(sink).tap do |log|
        log.formatter = proc { |severity, _t, _p, message| "#{severity} #{message}\n" }
      end
    )
    allow(mock_client).to receive(:fetch_resource).and_return(
      { status: 200, body: { login: "octocat", full_name: "octocat/Hello-World" },
        rate_limit: Github::RateLimit.unknown }
    )
  end

  describe "logs indicate ingestion behaviour" do
    it "reports the lifecycle, the counts, and the rate-limit posture on one run id" do
      allow(mock_client).to receive(:fetch_events).and_return(healthy_response)

      summary = runner.run_once
      output = sink.string

      expect(output).to include("event=ingestion.started")
      expect(output).to include("event=ingestion.fetched", "events=2")
      expect(output).to include("event=ingestion.filtered", "push_events=1", "rejected=1")
      expect(output).to include("event=ingestion.processed", "inserted=1")
      expect(output).to include("event=ingestion.finished")
      expect(output).to include("remaining=50")

      run_ids = output.scan(/run_id=(\w+)/).flatten.uniq
      expect(run_ids).to eq([summary.run_id])
    end
  end

  describe "malformed data is handled gracefully" do
    it "skips the bad event, keeps the good one, and says why" do
      malformed = { id: "evt_bad", type: "PushEvent", actor: { id: 9 }, repo: { id: 9 },
                    payload: {}, created_at: "2026-07-21T12:02:00Z" }
      allow(mock_client).to receive(:fetch_events)
        .and_return(healthy_response(body: events + [malformed]))

      summary = runner.run_once

      expect(summary.inserted_count).to eq(1)
      expect(summary.malformed_count).to eq(1)
      expect(PushEvent.count).to eq(1)
      expect(sink.string).to include("event=ingestion.malformed", "event_id=evt_bad")
    end

    it "survives a response whose body is not a list of events" do
      allow(mock_client).to receive(:fetch_events).and_return(healthy_response(body: nil))

      expect { runner.run_once }.not_to raise_error
      expect(PushEvent.count).to eq(0)
    end
  end

  describe "logs failures and retries" do
    # Regression: the runner built its client without a logger, so retries were
    # silent in real runs even though the client-level spec injected one.
    it "surfaces retry attempts from a runner that built its own client" do
      allow(Ingestion.config).to receive(:retry_base_delay).and_return(0.0)
      WebMock.enable!
      stub_request(:get, Ingestion.config.events_url)
        .to_timeout.then
        .to_return(status: 200, body: "[]")

      Ingestion::Runner.new.run_once

      expect(sink.string).to include("event=http.retrying", "attempt=1/3")
      expect(sink.string).to match(/run_id=\w+ event=http\.retrying/)
    end
  end

  describe "does not crash-loop on transient failures" do
    it "abandons the cycle and returns a summary instead of raising" do
      allow(mock_client).to receive(:fetch_events)
        .and_raise(Github::Client::TransientError.new("upstream down"))

      expect { runner.run_once }.not_to raise_error
      expect(sink.string).to include("event=ingestion.cycle_failed", "TransientError")
    end

    it "reports an exhausted budget and the action taken, without raising" do
      exhausted = Github::RateLimit.new(limit: 60, remaining: 0, reset: nil)
      allow(mock_client).to receive(:fetch_events)
        .and_raise(Github::Client::TransientError.new("Rate limited: HTTP 429", rate_limit: exhausted))

      summary = runner.run_once

      expect(summary.rate_limit.exhausted?).to be true
      expect(sink.string).to include("event=ingestion.rate_limited", %(action="cycle abandoned"))
    end

    it "does not swallow a permanent error silently" do
      allow(mock_client).to receive(:fetch_events)
        .and_raise(Github::Client::PermanentError.new("HTTP error: 404"))

      expect { runner.run_once }.not_to raise_error
      expect(sink.string).to include("ERROR", "PermanentError")
    end
  end

  describe "graceful shutdown" do
    it "stops the loop after the in-flight cycle when asked to stop" do
      allow(mock_client).to receive(:fetch_events).and_return(healthy_response)
      allow(runner).to receive(:pause) { runner.stop! }

      expect { Timeout.timeout(5) { runner.run_loop } }.not_to raise_error
      expect(PushEvent.count).to eq(1)
    end

    # Regression: a plain sleep(poll_interval) left SIGTERM waiting until the interval
    # elapsed, so Docker escalated to SIGKILL and the container exited 137.
    it "wakes from a long poll interval promptly instead of sleeping through the signal" do
      config = instance_double(
        Ingestion::Config, events_url: "https://api.github.com/events", request_timeout: 5,
        max_attempts: 3, retry_base_delay: 0.0, rate_limit_reserve: 10, poll_interval: 300
      )
      looping = Ingestion::Runner.new(client: mock_client, config: config)
      allow(mock_client).to receive(:fetch_events).and_return(healthy_response)

      thread = Thread.new { looping.run_loop }
      sleep(0.3)
      looping.stop!("TERM")

      expect(thread.join(5)).to eq(thread), "loop did not exit within 5s of stop!"
      expect(sink.string).to include("event=ingestion.shutdown", "signal=TERM")
    end
  end
end
