require "rails_helper"

RSpec.describe Github::RateLimit do
  def response_with(headers)
    instance_double(Net::HTTPResponse).tap do |response|
      allow(response).to receive(:[]) { |key| headers[key] }
    end
  end

  describe ".from_response" do
    it "parses the rate-limit headers" do
      reset = 1_784_000_000
      limit = described_class.from_response(
        response_with(
          "x-ratelimit-limit" => "60",
          "x-ratelimit-remaining" => "42",
          "x-ratelimit-reset" => reset.to_s
        )
      )

      expect(limit.limit).to eq(60)
      expect(limit.remaining).to eq(42)
      expect(limit.reset_at).to eq(Time.at(reset).utc)
      expect(limit).to be_known
    end

    it "is unknown when the headers are absent" do
      limit = described_class.from_response(response_with({}))

      expect(limit).not_to be_known
      expect(limit.remaining).to be_nil
      expect(limit.reset_at).to be_nil
    end

    it "is unknown when the headers are malformed" do
      limit = described_class.from_response(
        response_with("x-ratelimit-remaining" => "not-a-number")
      )

      expect(limit).not_to be_known
    end
  end

  describe "#exhausted?" do
    it "is true at zero remaining" do
      expect(described_class.new(limit: 60, remaining: 0, reset: nil)).to be_exhausted
    end

    it "is false with budget left" do
      expect(described_class.new(limit: 60, remaining: 1, reset: nil)).not_to be_exhausted
    end

    it "is false when the budget is unknown" do
      expect(described_class.unknown).not_to be_exhausted
    end
  end

  describe "#to_s" do
    it "renders the posture an operator needs" do
      reset = 1_784_000_000
      limit = described_class.new(limit: 60, remaining: 42, reset: reset)

      expect(limit.to_s).to eq("remaining=42/60 reset_at=#{Time.at(reset).utc.iso8601}")
    end

    it "says so when the budget is unknown" do
      expect(described_class.unknown.to_s).to eq("remaining=unknown")
    end
  end

  describe "#spendable" do
    it "returns the budget above the reserve" do
      expect(described_class.new(limit: 60, remaining: 30, reset: nil).spendable(10)).to eq(20)
    end

    it "floors at zero rather than going negative" do
      expect(described_class.new(limit: 60, remaining: 3, reset: nil).spendable(10)).to eq(0)
    end

    it "returns nil when the budget is unknown" do
      expect(described_class.unknown.spendable(10)).to be_nil
    end
  end
end
