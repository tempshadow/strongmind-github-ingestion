module Ingestion
  class RunLogger
    def initialize(run_id)
      @run_id = run_id
      @logger = Rails.logger
    end

    def start(mode:, interval: nil)
      @logger.info "[#{@run_id}] Ingestion started mode=#{mode} interval=#{interval}s"
    end

    def fetched(count)
      @logger.info "[#{@run_id}] Fetched #{count} events from GitHub"
    end

    def filtered(push_count, rejected_count)
      @logger.info "[#{@run_id}] Filtered: #{push_count} PushEvents, rejected #{rejected_count} other types"
    end

    def processed(inserted, duplicates, malformed)
      @logger.info "[#{@run_id}] Processed: #{inserted} inserted, #{duplicates} duplicates, #{malformed} malformed"
    end

    def rate_limit(remaining, limit, reset_at, action)
      @logger.info "[#{@run_id}] Rate limit: #{remaining}/#{limit} remaining, " \
                   "reset at #{reset_at}, action=#{action}"
    end

    def enrichment_summary(cache_hits, fetches, skipped)
      @logger.info "[#{@run_id}] Enrichment: #{cache_hits} cache hits, " \
                   "#{fetches} fetches, #{skipped} skipped"
    end

    def error(message, event_id: nil)
      msg = "[#{@run_id}] Error: #{message}"
      msg += " (event_id=#{event_id})" if event_id
      @logger.error msg
    end

    def debug(message)
      @logger.debug "[#{@run_id}] #{message}"
    end

    def finished(exit_code)
      @logger.info "[#{@run_id}] Ingestion finished with exit code #{exit_code}"
    end
  end
end
