require "rails_helper"

RSpec.describe Actor do
  it "uses the GitHub actor ID as its primary key" do
    actor = described_class.create!(id: 583231, login: "octocat", raw_json: { login: "octocat" })

    expect(described_class.find(583231)).to eq(actor)
  end

  it "requires a raw payload" do
    expect { described_class.create!(id: 1, login: "octocat") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects a second row with the same GitHub ID" do
    described_class.create!(id: 1, raw_json: { login: "a" })

    expect { described_class.create!(id: 1, raw_json: { login: "b" }) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "links to the push events that reference it" do
    described_class.create!(id: 1, raw_json: { login: "a" })
    PushEvent.create!(github_event_id: "evt_1", push_id: 1, actor_id: 1, raw_json: { id: "evt_1" })

    expect(described_class.find(1).push_events.pluck(:push_id)).to eq([1])
  end
end
