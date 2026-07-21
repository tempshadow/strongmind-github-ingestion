require "rails_helper"

RSpec.describe Ingestion::Enricher do
  let(:client) { instance_double(Github::Client) }

  let(:actor_url) { "https://api.github.com/users/octocat" }
  let(:repo_url) { "https://api.github.com/repos/octocat/Hello-World" }

  let(:actor_body) do
    JSON.parse(File.read("spec/fixtures/github/actor.json"), symbolize_names: true)
  end

  let(:repository_body) do
    JSON.parse(File.read("spec/fixtures/github/repository.json"), symbolize_names: true)
  end

  def event(actor_id: 583231, repo_id: 1296269, push_id: 1)
    {
      id: "evt_#{push_id}",
      type: "PushEvent",
      actor: { id: actor_id, login: "octocat", url: actor_url },
      repo: { id: repo_id, name: "octocat/Hello-World", url: repo_url },
      payload: { push_id: push_id, ref: "refs/heads/main" }
    }
  end

  def unlimited_response(body)
    { status: 200, body: body, rate_limit: Github::RateLimit.unknown }
  end

  before do
    # A bare stub so `have_received` can assert that nothing was fetched.
    allow(client).to receive(:fetch_resource)
  end

  def stub_fetches
    allow(client).to receive(:fetch_resource).with(actor_url)
                                             .and_return(unlimited_response(actor_body))
    allow(client).to receive(:fetch_resource).with(repo_url)
                                             .and_return(unlimited_response(repository_body))
  end

  describe "#enrich" do
    it "fetches and persists the actor and the repository" do
      stub_fetches

      result = described_class.new([event], client: client).enrich

      expect(result.fetches).to eq(2)
      expect(Actor.find(583231)).to have_attributes(
        login: "octocat",
        url: actor_url,
        avatar_url: "https://avatars.githubusercontent.com/u/583231?v=4"
      )
      expect(Repository.find(1296269)).to have_attributes(
        name: "Hello-World",
        full_name: "octocat/Hello-World",
        url: repo_url
      )
    end

    it "retains the raw response and records when it was fetched" do
      stub_fetches
      described_class.new([event], client: client).enrich

      actor = Actor.find(583231)
      expect(actor.raw_json[:node_id]).to eq("MDQ6VXNlcjU4MzIzMQ==")
      expect(actor.fetched_at).to be_present
    end

    it "issues no HTTP request when the record is already cached" do
      Actor.create!(id: 583231, login: "octocat", raw_json: { login: "octocat" })
      Repository.create!(id: 1296269, full_name: "octocat/Hello-World", raw_json: { id: 1 })

      result = described_class.new([event], client: client).enrich

      expect(client).not_to have_received(:fetch_resource)
      expect(result.cache_hits).to eq(2)
      expect(result.fetches).to eq(0)
    end

    it "does not refresh a cached record" do
      stub_fetches
      Actor.create!(id: 583231, login: "stale-login", raw_json: { login: "stale-login" })

      described_class.new([event], client: client).enrich

      expect(Actor.find(583231).login).to eq("stale-login")
    end

    it "deduplicates repeated references within one batch" do
      stub_fetches
      batch = [event(push_id: 1), event(push_id: 2), event(push_id: 3)]

      result = described_class.new(batch, client: client).enrich

      expect(client).to have_received(:fetch_resource).with(actor_url).once
      expect(client).to have_received(:fetch_resource).with(repo_url).once
      expect(result.fetches).to eq(2)
    end

    it "skips references that carry no id or url" do
      batch = [{ id: "evt_x", actor: { id: 1 }, repo: nil, payload: {} }]

      result = described_class.new(batch, client: client).enrich

      expect(result.fetches).to eq(0)
      expect(result.cache_hits).to eq(0)
      expect(Actor.count).to eq(0)
    end

    it "is idempotent across runs" do
      stub_fetches

      2.times { described_class.new([event], client: client).enrich }

      expect(Actor.count).to eq(1)
      expect(Repository.count).to eq(1)
    end

    it "counts a failed fetch without aborting the batch" do
      allow(client).to receive(:fetch_resource).with(actor_url)
                                               .and_raise(Github::Client::Error, "HTTP error: 404")
      allow(client).to receive(:fetch_resource).with(repo_url)
                                               .and_return(unlimited_response(repository_body))

      result = described_class.new([event], client: client).enrich

      expect(result.failures).to eq(1)
      expect(result.fetches).to eq(1)
      expect(result.errors).to contain_exactly("Actor#583231: HTTP error: 404")
      expect(Actor.count).to eq(0)
      expect(Repository.count).to eq(1)
    end

    it "survives a reference whose URL cannot be fetched" do
      bot_url = "https://api.github.com/users/github-actions[bot]"
      allow(client).to receive(:fetch_resource).with(bot_url)
                                               .and_raise(Github::Client::Error, "Invalid URL")
      allow(client).to receive(:fetch_resource).with(repo_url)
                                               .and_return(unlimited_response(repository_body))
      batch = [event.deep_merge(actor: { id: 99, url: bot_url })]

      result = described_class.new(batch, client: client).enrich

      expect(result.failures).to eq(1)
      expect(Repository.count).to eq(1)
    end

    it "tracks the budget from each enrichment response" do
      allow(client).to receive(:fetch_resource).with(actor_url).and_return(
        { status: 200, body: actor_body, rate_limit: rate_limit(11) }
      )
      allow(client).to receive(:fetch_resource).with(repo_url).and_return(
        { status: 200, body: repository_body, rate_limit: rate_limit(10) }
      )

      result = described_class.new([event], client: client, rate_limit: rate_limit(12)).enrich

      expect(result.fetches).to eq(2)
      expect(result.rate_limit.remaining).to eq(10)
    end
  end

  describe "budget enforcement" do
    let(:reserve) { Ingestion.config.rate_limit_reserve }

    it "skips enrichment entirely below the reserve" do
      result = described_class.new([event], client: client, rate_limit: rate_limit(reserve)).enrich

      expect(client).not_to have_received(:fetch_resource)
      expect(result.budget_skips).to eq(2)
      expect(result.fetches).to eq(0)
    end

    it "stops fetching once the responses report the reserve is reached" do
      allow(client).to receive(:fetch_resource).with(actor_url).and_return(
        { status: 200, body: actor_body, rate_limit: rate_limit(reserve) }
      )

      result = described_class.new([event], client: client, rate_limit: rate_limit(reserve + 1)).enrich

      expect(client).to have_received(:fetch_resource).with(actor_url).once
      expect(client).not_to have_received(:fetch_resource).with(repo_url)
      expect(result.fetches).to eq(1)
      expect(result.budget_skips).to eq(1)
    end

    it "proceeds when the budget is unknown" do
      stub_fetches

      result = described_class.new([event], client: client, rate_limit: Github::RateLimit.unknown).enrich

      expect(result.fetches).to eq(2)
      expect(result.budget_skips).to eq(0)
    end
  end

  def rate_limit(remaining)
    Github::RateLimit.new(limit: 60, remaining: remaining, reset: nil)
  end
end
