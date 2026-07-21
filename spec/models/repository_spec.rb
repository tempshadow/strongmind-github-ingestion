require "rails_helper"

RSpec.describe Repository do
  it "uses the GitHub repository ID as its primary key" do
    repo = described_class.create!(id: 1296269, full_name: "octocat/Hello-World",
                                   raw_json: { id: 1296269 })

    expect(described_class.find(1296269)).to eq(repo)
  end

  it "requires a raw payload" do
    expect { described_class.create!(id: 1, full_name: "a/b") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects two rows with the same full name" do
    described_class.create!(id: 1, full_name: "a/b", raw_json: { id: 1 })

    expect { described_class.create!(id: 2, full_name: "a/b", raw_json: { id: 2 }) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "links to the push events that reference it" do
    described_class.create!(id: 1, full_name: "a/b", raw_json: { id: 1 })
    PushEvent.create!(github_event_id: "evt_1", push_id: 1, repo_id: 1, raw_json: { id: "evt_1" })

    expect(described_class.find(1).push_events.pluck(:push_id)).to eq([1])
  end
end
