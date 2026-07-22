# frozen_string_literal: true

module Github
  class RateLimit
    HEADER_LIMIT = "x-ratelimit-limit"
    HEADER_REMAINING = "x-ratelimit-remaining"
    HEADER_RESET = "x-ratelimit-reset"

    attr_reader :limit, :remaining, :reset_at

    def self.from_response(response)
      new(
        limit: response[HEADER_LIMIT],
        remaining: response[HEADER_REMAINING],
        reset: response[HEADER_RESET]
      )
    end

    def self.unknown
      new(limit: nil, remaining: nil, reset: nil)
    end

    def initialize(limit:, remaining:, reset:)
      @limit = to_integer(limit)
      @remaining = to_integer(remaining)
      @reset_at = to_time(reset)
    end

    # Absent or malformed headers mean we do not know the budget, not that it is unlimited.
    def known?
      !@remaining.nil?
    end

    def exhausted?
      known? && @remaining.zero?
    end

    # Requests spendable above the reserve floor. nil when the budget is unknown.
    def spendable(reserve)
      return nil unless known?

      [@remaining - reserve, 0].max
    end

    def to_s
      return "remaining=unknown" unless known?

      "remaining=#{@remaining}/#{@limit || '?'} reset_at=#{@reset_at&.iso8601 || '?'}"
    end

    private

    def to_integer(value)
      Integer(value.to_s.strip, exception: false)
    end

    def to_time(value)
      epoch = to_integer(value)
      epoch && Time.at(epoch).utc
    end
  end
end
