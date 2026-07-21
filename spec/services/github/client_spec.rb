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
  end
end
