require "rails_helper"

RSpec.describe Ingestion::RunLogger do
  let(:sink) { StringIO.new }
  let(:logger) do
    ActiveSupport::Logger.new(sink).tap do |log|
      log.formatter = proc { |severity, _time, _progname, message| "#{severity} #{message}\n" }
    end
  end
  let(:run_logger) { described_class.new("abc123", logger: logger) }

  def output
    sink.string
  end

  it "correlates every line with the run id" do
    run_logger.started(mode: "once")
    run_logger.processed(inserted: 2, duplicates: 1, malformed: 0)

    expect(output.lines.length).to eq(2)
    expect(output.lines).to all(include("run_id=abc123"))
  end

  it "names the event and emits the counts an operator needs" do
    run_logger.processed(inserted: 2, duplicates: 1, malformed: 3)

    expect(output).to include("event=ingestion.processed")
    expect(output).to include("inserted=2", "duplicates=1", "malformed=3")
  end

  it "reports rate-limit posture and the action taken" do
    rate_limit = Github::RateLimit.new(limit: 60, remaining: 0, reset: 1_800_000_000)

    run_logger.rate_limited(rate_limit: rate_limit, action: "cycle abandoned")

    expect(output).to include("event=ingestion.rate_limited")
    expect(output).to include("remaining=0")
    expect(output).to include(%(action="cycle abandoned"))
  end

  it "logs retries at warn and failures at error" do
    run_logger.retrying(url: "https://api.github.com/events", attempt: 1, max: 3,
                        delay: 1.5, reason: "Net::ReadTimeout")
    run_logger.cycle_failed(error: Github::Client::TransientError.new("upstream down"))

    expect(output).to include("WARN", "event=http.retrying", "attempt=1/3", "delay_s=1.5")
    expect(output).to include("ERROR", "event=ingestion.cycle_failed", "TransientError")
  end

  it "quotes values containing whitespace so pairs stay parseable" do
    run_logger.malformed_event(event_id: "evt_1", reason: "missing push id")

    expect(output).to include(%(reason="missing push id"))
  end
end
