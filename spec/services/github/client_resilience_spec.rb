require "rails_helper"

RSpec.describe Github::Client, "resilience" do
  let(:events_url) { "https://api.github.com/events" }

  # Zero base delay keeps the suite fast; the backoff arithmetic is asserted separately.
  let(:client) do
    described_class.new(url: events_url, timeout: 5, max_attempts: 3, retry_base_delay: 0.0)
  end

  before { WebMock.enable! }

  describe "error classification" do
    it "treats a 500 as transient" do
      stub_request(:get, events_url).to_return(status: 500)

      expect { client.fetch_events }.to raise_error(Github::Client::TransientError, /500/)
    end

    it "treats a 429 as transient and carries the rate limit" do
      stub_request(:get, events_url)
        .to_return(status: 429, headers: { "X-RateLimit-Remaining" => "0", "X-RateLimit-Limit" => "60" })

      expect { client.fetch_events }.to raise_error(Github::Client::TransientError) do |error|
        expect(error.rate_limit.remaining).to eq(0)
      end
    end

    it "treats a 403 with an exhausted budget as transient, not permanent" do
      stub_request(:get, events_url)
        .to_return(status: 403, headers: { "X-RateLimit-Remaining" => "0" })

      expect { client.fetch_events }.to raise_error(Github::Client::TransientError)
    end

    it "treats a 403 with budget remaining as permanent" do
      stub_request(:get, events_url)
        .to_return(status: 403, headers: { "X-RateLimit-Remaining" => "42" })

      expect { client.fetch_events }.to raise_error(Github::Client::PermanentError)
    end

    it "treats a 404 as permanent" do
      stub_request(:get, events_url).to_return(status: 404)

      expect { client.fetch_events }.to raise_error(Github::Client::PermanentError, /404/)
    end

    it "treats an unparseable body as permanent" do
      stub_request(:get, events_url).to_return(status: 200, body: "not json")

      expect { client.fetch_events }.to raise_error(Github::Client::PermanentError, /Invalid JSON/)
    end
  end

  describe "retries" do
    it "recovers when a transient failure is followed by success" do
      stub_request(:get, events_url)
        .to_timeout.then
        .to_return(status: 200, body: "[]")

      expect(client.fetch_events[:body]).to eq([])
    end

    it "gives up after max_attempts rather than retrying forever" do
      stub_request(:get, events_url).to_timeout

      expect { client.fetch_events }.to raise_error(Github::Client::TransientError)
      expect(WebMock).to have_requested(:get, events_url).times(3)
    end

    it "does not retry a permanent error" do
      stub_request(:get, events_url).to_return(status: 404)

      expect { client.fetch_events }.to raise_error(Github::Client::PermanentError)
      expect(WebMock).to have_requested(:get, events_url).once
    end

    it "backs off for longer on each successive attempt" do
      slow_client = described_class.new(url: events_url, timeout: 5, max_attempts: 3, retry_base_delay: 1.0)
      stub_request(:get, events_url).to_timeout
      delays = []
      allow_any_instance_of(described_class).to receive(:sleep) { |_, seconds| delays << seconds }

      expect { slow_client.fetch_events }.to raise_error(Github::Client::TransientError)

      expect(delays.length).to eq(2)
      expect(delays.first).to be_between(1.0, 2.0)
      expect(delays.last).to be_between(2.0, 3.0)
      expect(delays.last).to be > delays.first
    end

    it "reports retries to the logger so operators see them" do
      run_logger = instance_spy(Ingestion::RunLogger)
      stub_request(:get, events_url).to_timeout.then.to_return(status: 200, body: "[]")

      described_class.new(url: events_url, timeout: 5, max_attempts: 3,
                          retry_base_delay: 0.0, logger: run_logger).fetch_events

      expect(run_logger).to have_received(:retrying)
        .with(hash_including(url: events_url, attempt: 1, max: 3))
    end
  end
end
