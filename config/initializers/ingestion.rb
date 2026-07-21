module Ingestion
  class Config
    include Singleton

    attr_reader :poll_interval, :rate_limit_reserve, :request_timeout, :max_retries, :retry_base_delay

    def initialize
      @poll_interval = ENV["POLL_INTERVAL_SECONDS"]&.to_i || 60
      @rate_limit_reserve = ENV["RATE_LIMIT_RESERVE"]&.to_i || 10
      @request_timeout = ENV["REQUEST_TIMEOUT_SECONDS"]&.to_i || 10
      @max_retries = ENV["MAX_RETRIES"]&.to_i || 3
      @retry_base_delay = ENV["RETRY_BASE_DELAY_SECONDS"]&.to_i || 1
    end
  end

  def self.config
    Config.instance
  end
end
