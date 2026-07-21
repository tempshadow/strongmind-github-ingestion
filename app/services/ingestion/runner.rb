module Ingestion
  class Runner
    def initialize(client: nil, config: nil)
      @client = client || Github::Client.new
      @config = config || Config.instance
    end

    def run_once
      summary = RunSummary.new
      logger = RunLogger.new(summary.run_id)

      logger.start(mode: "once")

      run_cycle(summary, logger)

      logger.finished(0)
      summary
    end

    def run_loop
      loop do
        summary = RunSummary.new
        logger = RunLogger.new(summary.run_id)

        logger.start(mode: "loop", interval: @config.poll_interval)

        run_cycle(summary, logger)

        logger.finished(0)

        if summary.rate_limit.exhausted?
          sleep_until = summary.rate_limit.reset_at
          logger.debug("Rate limit exhausted, sleeping until #{sleep_until}")
          sleep((sleep_until - Time.current).ceil)
        else
          sleep(@config.poll_interval)
        end
      end
    end

    private

    def run_cycle(summary, logger)
      response = @client.fetch_events
      summary.fetched_count = response[:body].length
      logger.fetched(summary.fetched_count)

      rate_limit = Github::RateLimit.from_response(response[:rate_limit])
      summary.rate_limit = rate_limit
      logger.rate_limit(rate_limit.remaining, rate_limit.limit, rate_limit.reset_at, "continue")

      filtered = EventFilter.new(response[:body]).filter
      summary.filtered_count = filtered.push_events.length
      logger.filtered(filtered.push_events.length, filtered.rejected_count)

      process_events(filtered.push_events, summary, logger)
    end

    def process_events(push_events, summary, logger)
      push_events.each do |event|
        processor = EventProcessor.new(event)
        processor.process

        if processor.inserted?
          summary.inserted_count += 1
        elsif processor.duplicate?
          summary.duplicate_count += 1
          logger.debug("Duplicate event: #{processor.event_id}")
        elsif processor.malformed?
          summary.malformed_count += 1
          logger.error(processor.error_message, event_id: processor.event_id)
        end
      end

      logger.processed(summary.inserted_count, summary.duplicate_count, summary.malformed_count)
    end
  end
end
