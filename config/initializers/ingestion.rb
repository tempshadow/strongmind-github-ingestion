module Ingestion
  class Config
    include Singleton

    attr_reader :events_url, :poll_interval, :request_timeout, :rate_limit_reserve,
                :max_attempts, :retry_base_delay

    def initialize
      @events_url = ENV["GITHUB_EVENTS_URL"] || "https://api.github.com/events"
      @poll_interval = ENV["POLL_INTERVAL_SECONDS"]&.to_i || 60
      @request_timeout = ENV["REQUEST_TIMEOUT_SECONDS"]&.to_i || 10
      @rate_limit_reserve = ENV["RATE_LIMIT_RESERVE"]&.to_i || 10
      @max_attempts = ENV["MAX_ATTEMPTS"]&.to_i || 3
      @retry_base_delay = ENV["RETRY_BASE_DELAY_SECONDS"]&.to_f || 1.0
    end
  end

  def self.config
    Config.instance
  end
end
