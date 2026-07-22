# frozen_string_literal: true

module Ingestion
  class RunLogger
    # The stable event vocabulary an operator (or a log parser) keys on.
    module Event
      STARTED = "ingestion.started"
      FETCHED = "ingestion.fetched"
      FILTERED = "ingestion.filtered"
      PROCESSED = "ingestion.processed"
      ENRICHED = "ingestion.enriched"
      MALFORMED = "ingestion.malformed"
      RATE_LIMITED = "ingestion.rate_limited"
      CYCLE_FAILED = "ingestion.cycle_failed"
      FINISHED = "ingestion.finished"
      SHUTDOWN = "ingestion.shutdown"
      SLEEPING = "ingestion.sleeping"
      RETRYING = "http.retrying"
    end

    def initialize(run_id, logger: Rails.logger)
      @run_id = run_id
      @logger = logger
    end

    def started(mode:)
      info(Event::STARTED, mode: mode)
    end

    def fetched(count:, rate_limit:)
      info(Event::FETCHED, events: count, rate_limit: rate_limit.to_s)
    end

    def filtered(push_events:, rejected:)
      info(Event::FILTERED, push_events: push_events, rejected: rejected)
    end

    def processed(inserted:, duplicates:, malformed:)
      info(Event::PROCESSED, inserted: inserted, duplicates: duplicates, malformed: malformed)
    end

    def enriched(hits:, fetches:, skipped:, failed:)
      info(Event::ENRICHED, cache_hits: hits, fetches: fetches, skipped: skipped, failed: failed)
    end

    def malformed_event(event_id:, reason:)
      warn(Event::MALFORMED, event_id: event_id, reason: reason)
    end

    def retrying(url:, attempt:, max:, delay:, reason:)
      warn(Event::RETRYING, url: url, attempt: "#{attempt}/#{max}", delay_s: delay, reason: reason)
    end

    def rate_limited(rate_limit:, action:)
      warn(Event::RATE_LIMITED, rate_limit: rate_limit.to_s, action: action)
    end

    def cycle_failed(error:)
      error(Event::CYCLE_FAILED, error: error.class.name, message: error.message)
    end

    def finished(summary:)
      info(Event::FINISHED, result: summary.to_s)
    end

    def shutdown(signal:)
      info(Event::SHUTDOWN, signal: signal)
    end

    def sleeping(seconds:, reason:)
      info(Event::SLEEPING, seconds: seconds.round, reason: reason)
    end

    private

    def info(event, **fields)
      @logger.info(format_line(event, fields))
    end

    def warn(event, **fields)
      @logger.warn(format_line(event, fields))
    end

    def error(event, **fields)
      @logger.error(format_line(event, fields))
    end

    def format_line(event, fields)
      pairs = fields.map { |key, value| "#{key}=#{quote(value)}" }
      (["run_id=#{@run_id}", "event=#{event}"] + pairs).join(" ")
    end

    def quote(value)
      string = value.to_s
      string.match?(/\s/) ? string.inspect : string
    end
  end
end
