module Ingestion
  class Runner
    def initialize(client: nil, config: nil)
      @client = client || Github::Client.new
      @config = config || Config.instance
    end

    def run_once
      summary = RunSummary.new
      run_cycle(summary)
      summary
    end

    def run_loop
      loop do
        summary = RunSummary.new
        run_cycle(summary)
        sleep(@config.poll_interval)
      end
    end

    private

    def run_cycle(summary)
      response = @client.fetch_events
      summary.fetched_count = response[:body].length
      # Read the budget before deciding anything, so enrichment is governed by a
      # measured number rather than an assumed one.
      summary.rate_limit = response[:rate_limit] || Github::RateLimit.unknown

      # The audit trail covers every event type, so it is written before filtering.
      record_raw_events(response[:body])

      filtered = EventFilter.new(response[:body]).filter
      summary.filtered_count = filtered.push_events.length

      process_events(filtered.push_events, summary)
      enrich_events(filtered.push_events, summary)
    end

    def enrich_events(push_events, summary)
      enricher = Enricher.new(
        push_events,
        client: @client,
        rate_limit: summary.rate_limit,
        config: @config
      ).enrich

      summary.enrichment_hits = enricher.cache_hits
      summary.enrichment_fetches = enricher.fetches
      summary.enrichment_skips = enricher.budget_skips
      summary.enrichment_failures = enricher.failures
      summary.rate_limit = enricher.rate_limit
    end

    def record_raw_events(events)
      events.each do |event|
        RawEvent.create!(event_id: event[:id], payload: event)
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end

    def process_events(push_events, summary)
      push_events.each do |event|
        processor = EventProcessor.new(event)
        processor.process

        if processor.inserted?
          summary.inserted_count += 1
        elsif processor.duplicate?
          summary.duplicate_count += 1
        elsif processor.malformed?
          summary.malformed_count += 1
        end
      end
    end
  end
end
