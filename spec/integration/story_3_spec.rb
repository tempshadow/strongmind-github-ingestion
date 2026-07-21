require "rails_helper"

RSpec.describe "Story 3: Enrich Push Events" do
  let(:runner) { Ingestion::Runner.new(client: Github::Client.new(url: events_url, timeout: 5)) }

  let(:events_url) { "https://api.github.com/events" }
  let(:actor_url) { "https://api.github.com/users/octocat" }
  let(:repo_url) { "https://api.github.com/repos/octocat/Hello-World" }

  let(:events) do
    # Two pushes by the same actor to the same repository: one fetch each, not two.
    [1, 2].map do |push_id|
      {
        id: "evt_#{push_id}",
        type: "PushEvent",
        actor: { id: 583231, login: "octocat", url: actor_url },
        repo: { id: 1296269, name: "octocat/Hello-World", url: repo_url },
        payload: { push_id: push_id, ref: "refs/heads/main", head: "abc", before: "def" },
        created_at: "2026-07-21T12:00:00Z"
      }
    end
  end

  def stub_feed(remaining: 55)
    stub_request(:get, events_url).to_return(
      status: 200,
      body: events.to_json,
      headers: rate_limit_headers(remaining)
    )
  end

  def stub_enrichment(remaining: 53)
    stub_request(:get, actor_url).to_return(
      status: 200,
      body: File.read("spec/fixtures/github/actor.json"),
      headers: rate_limit_headers(remaining)
    )
    stub_request(:get, repo_url).to_return(
      status: 200,
      body: File.read("spec/fixtures/github/repository.json"),
      headers: rate_limit_headers(remaining)
    )
  end

  def rate_limit_headers(remaining)
    {
      "X-RateLimit-Limit" => "60",
      "X-RateLimit-Remaining" => remaining.to_s,
      "X-RateLimit-Reset" => (Time.now.to_i + 3600).to_s
    }
  end

  it "populates actors and repositories and links them to their push events" do
    stub_feed
    stub_enrichment

    summary = runner.run_once

    expect(summary.enrichment_fetches).to eq(2)
    expect(summary.enrichment_hits).to eq(0)

    push_event = PushEvent.find_by(push_id: 1)
    expect(push_event.actor.login).to eq("octocat")
    expect(push_event.repository.full_name).to eq("octocat/Hello-World")
  end

  it "fetches each distinct actor and repository once per batch" do
    stub_feed
    stub_enrichment

    runner.run_once

    expect(a_request(:get, actor_url)).to have_been_made.once
    expect(a_request(:get, repo_url)).to have_been_made.once
    expect(PushEvent.count).to eq(2)
  end

  it "serves the second run from the cache without any enrichment request" do
    stub_feed
    stub_enrichment
    runner.run_once

    WebMock.reset_executed_requests!
    summary = runner.run_once

    expect(summary.enrichment_hits).to eq(2)
    expect(summary.enrichment_fetches).to eq(0)
    expect(a_request(:get, actor_url)).not_to have_been_made
    expect(a_request(:get, repo_url)).not_to have_been_made
    expect(Actor.count).to eq(1)
    expect(Repository.count).to eq(1)
  end

  it "persists events unenriched when the budget is at the reserve" do
    stub_feed(remaining: Ingestion.config.rate_limit_reserve)
    stub_enrichment

    summary = runner.run_once

    expect(summary.inserted_count).to eq(2)
    expect(summary.enrichment_skips).to eq(2)
    expect(summary.enrichment_fetches).to eq(0)
    expect(a_request(:get, actor_url)).not_to have_been_made

    # Unenriched events are a valid state: the projection is still queryable.
    expect(PushEvent.pluck(:repo_id, :ref)).to all(eq([1296269, "refs/heads/main"]))
    expect(Actor.count).to eq(0)
  end

  it "records the rate-limit posture on the summary" do
    stub_feed(remaining: 55)
    stub_enrichment(remaining: 53)

    summary = runner.run_once

    expect(summary.rate_limit.remaining).to eq(53)
    expect(summary.rate_limit.limit).to eq(60)
  end
end
