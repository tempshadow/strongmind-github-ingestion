require "rails_helper"

RSpec.describe "Story 2: Persist Raw and Structured Data" do
  let(:mock_client) { instance_double(Github::Client) }
  let(:runner) { Ingestion::Runner.new(client: mock_client) }

  let(:github_events) do
    [
      {
        id: "evt_push_1",
        type: "PushEvent",
        actor: { id: 1, login: "octocat", url: "https://api.github.com/users/octocat" },
        repo: { id: 1296269, name: "Hello-World", url: "https://api.github.com/repos/octocat/Hello-World" },
        payload: {
          push_id: 1,
          ref: "refs/heads/main",
          head: "0d1a26e67d8f5eaf100f6b73408ac5e3e8fab507",
          before: "6dcb09b5b57875f334f61aebed695e2e4193db5e"
        },
        created_at: "2026-07-20T12:00:00Z"
      }
    ]
  end

  before do
    allow(mock_client).to receive(:fetch_events).and_return({
      status: 200,
      body: github_events
    })
  end

  it "makes the required fields queryable without parsing JSON" do
    runner.run_once

    # Selecting only the projected columns proves no JSON parsing is needed.
    row = PushEvent.where(push_id: 1)
                   .pick(:repo_id, :push_id, :ref, :head_sha, :before_sha)

    expect(row).to eq([
      1296269,
      1,
      "refs/heads/main",
      "0d1a26e67d8f5eaf100f6b73408ac5e3e8fab507",
      "6dcb09b5b57875f334f61aebed695e2e4193db5e"
    ])
  end

  it "retains the raw payload alongside the projection" do
    runner.run_once

    event = PushEvent.find_by(push_id: 1)
    expect(event.raw_json[:actor][:login]).to eq("octocat")
    expect(event.raw_json[:payload][:head]).to eq(event.head_sha)
  end

  it "leaves structured columns null when the payload omits them" do
    sparse = github_events.first.merge(payload: { push_id: 99 }, repo: nil, actor: nil)
    allow(mock_client).to receive(:fetch_events).and_return({
      status: 200,
      body: [sparse]
    })

    runner.run_once

    event = PushEvent.find_by(push_id: 99)
    expect(event).to be_present
    expect(event.repo_id).to be_nil
    expect(event.ref).to be_nil
  end
end
