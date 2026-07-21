require "rails_helper"

RSpec.describe Github::Client do
  let(:client) { described_class.new(url: "https://api.github.com/events", timeout: 5) }

  before do
    WebMock.enable!
  end

  describe "#fetch_events" do
    it "makes a GET request with correct headers" do
      stub_request(:get, "https://api.github.com/events")
        .with(headers: { "User-Agent" => /StrongMind-GitHub-Ingestion/ })
        .to_return(status: 200, body: "[]")

      response = client.fetch_events
      expect(response[:status]).to eq(200)
      expect(response[:body]).to eq([])
    end

    it "parses JSON response body" do
      events_body = File.read("spec/fixtures/github/events.json")
      stub_request(:get, "https://api.github.com/events")
        .to_return(status: 200, body: events_body)

      response = client.fetch_events
      expect(response[:body]).to be_an(Array)
      expect(response[:body].first[:type]).to eq("PushEvent")
    end

    it "treats an empty body as an empty event list" do
      stub_request(:get, "https://api.github.com/events")
        .to_return(status: 200, body: "")

      expect(client.fetch_events[:body]).to eq([])
    end

    it "raises on a non-success response" do
      stub_request(:get, "https://api.github.com/events").to_return(status: 500)

      expect { client.fetch_events }.to raise_error(Github::Client::Error, /500/)
    end

    it "raises on an unparseable body" do
      stub_request(:get, "https://api.github.com/events")
        .to_return(status: 200, body: "not json")

      expect { client.fetch_events }.to raise_error(Github::Client::Error, /Invalid JSON/)
    end

    it "captures the rate-limit headers" do
      stub_request(:get, "https://api.github.com/events").to_return(
        status: 200,
        body: "[]",
        headers: { "X-RateLimit-Limit" => "60", "X-RateLimit-Remaining" => "58" }
      )

      rate_limit = client.fetch_events[:rate_limit]
      expect(rate_limit.limit).to eq(60)
      expect(rate_limit.remaining).to eq(58)
    end

    it "reports an unknown budget when the headers are absent" do
      stub_request(:get, "https://api.github.com/events").to_return(status: 200, body: "[]")

      expect(client.fetch_events[:rate_limit]).not_to be_known
    end
  end

  describe "#fetch_resource" do
    let(:actor_url) { "https://api.github.com/users/octocat" }

    it "uses the same headers, parsing, and rate-limit capture as the feed request" do
      stub_request(:get, actor_url)
        .with(headers: { "User-Agent" => /StrongMind-GitHub-Ingestion/ })
        .to_return(
          status: 200,
          body: File.read("spec/fixtures/github/actor.json"),
          headers: { "X-RateLimit-Remaining" => "40" }
        )

      response = client.fetch_resource(actor_url)

      expect(response[:body][:login]).to eq("octocat")
      expect(response[:rate_limit].remaining).to eq(40)
    end

    it "raises on a non-success response" do
      stub_request(:get, actor_url).to_return(status: 404)

      expect { client.fetch_resource(actor_url) }
        .to raise_error(Github::Client::Error, /404/)
    end

    it "raises its own error class for an unparseable URL" do
      # Bot logins arrive with unescaped brackets in the feed.
      expect { client.fetch_resource("https://api.github.com/users/github-actions[bot]") }
        .to raise_error(Github::Client::Error, /Invalid URL/)
    end
  end
end
