module Github
  class RateLimit
    attr_reader :remaining, :limit, :reset

    def initialize(remaining, limit, reset)
      @remaining = remaining&.to_i
      @limit = limit&.to_i
      @reset = reset&.to_i
    end

    def self.from_response(rate_limit_hash)
      new(
        rate_limit_hash[:remaining],
        rate_limit_hash[:limit],
        rate_limit_hash[:reset]
      )
    end

    def exhausted?
      remaining&.zero?
    end

    def above_reserve?(reserve = 10)
      remaining&.>(reserve)
    end

    def reset_at
      Time.zone.at(reset) if reset
    end
  end
end
