# frozen_string_literal: true

module Ingestion
  # One ingestion pass: fetch, record raw, filter, persist, enrich. The Runner owns *when*
  # cycles happen; the Cycle owns *what* one cycle does.
  class Cycle
    def initialize(client:, logger:, config:)
      @client = client
      @logger = logger
      @config = config
    end

    def run(summary)
      events = fetch(summary)
      record_raw_events(events)

      push_events = filter(events, summary)
      process(push_events, summary)
      enrich(push_events, summary)
    end

    private

    def fetch(summary)
      response = @client.fetch_events
      events = Array(response[:body])
      summary.fetched_count = events.length
      # Read the budget before deciding anything, so enrichment spends a measured number.
      summary.rate_limit = response[:rate_limit] || Github::RateLimit.unknown
      @logger.fetched(count: summary.fetched_count, rate_limit: summary.rate_limit)
      events
    end

    # The audit trail covers every event type, so it is written before filtering. One upsert
    # for the batch (ON CONFLICT DO NOTHING) avoids an exception per duplicate on the
    # heavily-overlapping feed.
    def record_raw_events(events)
      now = Time.current
      rows = events.filter_map do |event|
        next log_missing_id(event) if event[:id].blank?

        { event_id: event[:id], payload: event, created_at: now, updated_at: now }
      end

      RawEvent.insert_all(rows, unique_by: :event_id) if rows.any?
    end

    def log_missing_id(event)
      @logger.malformed_event(event_id: event[:id].to_s, reason: "missing event id")
      nil
    end

    def filter(events, summary)
      filtered = EventFilter.new(events).filter
      summary.filtered_count = filtered.push_events.length
      @logger.filtered(push_events: summary.filtered_count, rejected: filtered.rejected_count)
      filtered.push_events
    end

    def process(push_events, summary)
      push_events.each do |event|
        record_outcome(EventProcessor.new(event).process, summary)
      end

      @logger.processed(inserted: summary.inserted_count, duplicates: summary.duplicate_count,
                        malformed: summary.malformed_count)
    end

    def record_outcome(processor, summary)
      if processor.inserted?
        summary.inserted_count += 1
      elsif processor.duplicate?
        summary.duplicate_count += 1
      elsif processor.malformed?
        summary.malformed_count += 1
        @logger.malformed_event(event_id: processor.event_id.to_s,
                                reason: processor.error_message.to_s)
      end
    end

    def enrich(push_events, summary)
      enricher = Enricher.new(
        push_events, client: @client, rate_limit: summary.rate_limit, config: @config
      ).enrich

      summary.enrichment_hits = enricher.cache_hits
      summary.enrichment_fetches = enricher.fetches
      summary.enrichment_skips = enricher.budget_skips
      summary.enrichment_failures = enricher.failures
      summary.rate_limit = enricher.rate_limit

      @logger.enriched(hits: summary.enrichment_hits, fetches: summary.enrichment_fetches,
                       skipped: summary.enrichment_skips, failed: summary.enrichment_failures)
    end
  end
end
