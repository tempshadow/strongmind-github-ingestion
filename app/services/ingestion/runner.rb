module Ingestion
  class Runner
    def initialize(client: nil, config: nil)
      @config = config || Config.instance
      @injected_client = client
      @stopping = false
    end

    def run_once
      summary = RunSummary.new
      logger = RunLogger.new(summary.run_id)

      logger.started(mode: "once")
      safe_run_cycle(summary, logger)
      logger.finished(summary: summary)

      summary
    end

    def run_loop
      trap_signals

      until @stopping
        summary = run_once
        break if @stopping

        pause(summary)
      end

      RunLogger.new("shutdown").shutdown(signal: @stop_signal || "none") if @stopping
    end

    def stop!(signal = "SIGTERM")
      @stopping = true
      @stop_signal = signal
    end

    private

    def trap_signals
      %w[INT TERM].each do |signal|
        # Trap context forbids most work, so record the intent and let the loop act on it.
        Signal.trap(signal) do
          @stopping = true
          @stop_signal = signal
        end
      end
    end

    # sleep(60) would leave a SIGTERM waiting up to a minute for the loop to notice.
    # Waking every second bounds shutdown latency without busy-waiting.
    def interruptible_sleep(seconds)
      deadline = Time.now.utc + seconds

      while !@stopping && Time.now.utc < deadline
        sleep([1, deadline - Time.now.utc].min)
      end
    end

    # A cycle that cannot complete is logged and abandoned; the process stays alive so a
    # transient upstream failure never becomes a container restart loop.
    def safe_run_cycle(summary, logger)
      run_cycle(summary, logger)
    rescue Github::Client::TransientError => e
      summary.rate_limit = e.rate_limit if e.rate_limit
      logger.rate_limited(rate_limit: summary.rate_limit, action: "cycle abandoned")
      logger.cycle_failed(error: e)
    rescue Github::Client::Error, ActiveRecord::ActiveRecordError => e
      logger.cycle_failed(error: e)
    end

    def pause(summary)
      logger = RunLogger.new(summary.run_id)

      if summary.rate_limit.exhausted? && summary.rate_limit.reset_at
        seconds = [(summary.rate_limit.reset_at - Time.now.utc).ceil, 1].max
        logger.sleeping(seconds: seconds, reason: "rate limit exhausted")
        interruptible_sleep(seconds)
      else
        logger.sleeping(seconds: @config.poll_interval, reason: "poll interval")
        interruptible_sleep(@config.poll_interval)
      end
    end

    # Built per cycle so the client's retry warnings carry this run's id.
    def client_for(logger)
      @injected_client || Github::Client.new(config: @config, logger: logger)
    end

    def run_cycle(summary, logger)
      client = client_for(logger)
      response = client.fetch_events
      events = Array(response[:body])
      summary.fetched_count = events.length
      # Read the budget before deciding anything, so enrichment is governed by a
      # measured number rather than an assumed one.
      summary.rate_limit = response[:rate_limit] || Github::RateLimit.unknown
      logger.fetched(count: summary.fetched_count, rate_limit: summary.rate_limit)

      # The audit trail covers every event type, so it is written before filtering.
      record_raw_events(events, logger)

      filtered = EventFilter.new(events).filter
      summary.filtered_count = filtered.push_events.length
      logger.filtered(push_events: summary.filtered_count, rejected: filtered.rejected_count)

      process_events(filtered.push_events, summary, logger)
      enrich_events(filtered.push_events, summary, logger, client)
    end

    def enrich_events(push_events, summary, logger, client)
      enricher = Enricher.new(
        push_events,
        client: client,
        rate_limit: summary.rate_limit,
        config: @config
      ).enrich

      summary.enrichment_hits = enricher.cache_hits
      summary.enrichment_fetches = enricher.fetches
      summary.enrichment_skips = enricher.budget_skips
      summary.enrichment_failures = enricher.failures
      summary.rate_limit = enricher.rate_limit

      logger.enriched(hits: summary.enrichment_hits, fetches: summary.enrichment_fetches,
                      skipped: summary.enrichment_skips, failed: summary.enrichment_failures)
    end

    def record_raw_events(events, logger)
      events.each do |event|
        RawEvent.create!(event_id: event[:id], payload: event)
      rescue ActiveRecord::RecordNotUnique
        next
      rescue ActiveRecord::NotNullViolation, ActiveRecord::RecordInvalid => e
        logger.malformed_event(event_id: event[:id].to_s, reason: e.class.name)
      end
    end

    def process_events(push_events, summary, logger)
      push_events.each do |event|
        processor = EventProcessor.new(event)
        processor.process

        if processor.inserted?
          summary.inserted_count += 1
        elsif processor.duplicate?
          summary.duplicate_count += 1
        elsif processor.malformed?
          summary.malformed_count += 1
          logger.malformed_event(event_id: processor.event_id.to_s,
                                 reason: processor.error_message.to_s)
        end
      end

      logger.processed(inserted: summary.inserted_count, duplicates: summary.duplicate_count,
                       malformed: summary.malformed_count)
    end
  end
end
