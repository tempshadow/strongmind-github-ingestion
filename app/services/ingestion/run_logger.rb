module Ingestion
  class RunLogger
    def initialize(run_id, logger: Rails.logger)
      @run_id = run_id
      @logger = logger
    end

    def started(mode:)
      info("ingestion.started", mode: mode)
    end

    def fetched(count:, rate_limit:)
      info("ingestion.fetched", events: count, rate_limit: rate_limit.to_s)
    end

    def filtered(push_events:, rejected:)
      info("ingestion.filtered", push_events: push_events, rejected: rejected)
    end

    def processed(inserted:, duplicates:, malformed:)
      info("ingestion.processed", inserted: inserted, duplicates: duplicates, malformed: malformed)
    end

    def enriched(hits:, fetches:, skipped:, failed:)
      info("ingestion.enriched", cache_hits: hits, fetches: fetches, skipped: skipped, failed: failed)
    end

    def malformed_event(event_id:, reason:)
      warn("ingestion.malformed", event_id: event_id, reason: reason)
    end

    def retrying(url:, attempt:, max:, delay:, reason:)
      warn("http.retrying", url: url, attempt: "#{attempt}/#{max}", delay_s: delay, reason: reason)
    end

    def rate_limited(rate_limit:, action:)
      warn("ingestion.rate_limited", rate_limit: rate_limit.to_s, action: action)
    end

    def cycle_failed(error:)
      error("ingestion.cycle_failed", error: error.class.name, message: error.message)
    end

    def finished(summary:)
      info("ingestion.finished", result: summary.to_s)
    end

    def shutdown(signal:)
      info("ingestion.shutdown", signal: signal)
    end

    def sleeping(seconds:, reason:)
      info("ingestion.sleeping", seconds: seconds.round, reason: reason)
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
