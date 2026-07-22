# frozen_string_literal: true

module Ingestion
  class Runner
    MODE_ONCE = "once"

    REASON_ABANDONED = "cycle abandoned"
    REASON_RATE_LIMIT = "rate limit exhausted"
    REASON_POLL_INTERVAL = "poll interval"

    STOP_SIGNALS = %w[INT TERM].freeze

    def initialize(client: nil, config: nil)
      @config = config || Config.instance
      @injected_client = client
      @stopping = false
    end

    def run_once
      summary = RunSummary.new
      logger = RunLogger.new(summary.run_id)

      logger.started(mode: MODE_ONCE)
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
      STOP_SIGNALS.each do |signal|
        # Trap context forbids most work, so record the intent and let the loop act on it.
        Signal.trap(signal) { stop!(signal) }
      end
    end

    # A cycle that cannot complete is logged and abandoned; the process stays alive so a
    # transient upstream failure never becomes a container restart loop.
    def safe_run_cycle(summary, logger)
      Cycle.new(client: client_for(logger), logger: logger, config: @config).run(summary)
    rescue Github::Client::TransientError => e
      summary.rate_limit = e.rate_limit if e.rate_limit
      logger.rate_limited(rate_limit: summary.rate_limit, action: REASON_ABANDONED)
      logger.cycle_failed(error: e)
    rescue Github::Client::Error, ActiveRecord::ActiveRecordError => e
      logger.cycle_failed(error: e)
    end

    def pause(summary)
      logger = RunLogger.new(summary.run_id)
      rate_limit = summary.rate_limit

      if rate_limit.exhausted? && rate_limit.reset_at
        seconds = [(rate_limit.reset_at - Time.now.utc).ceil, 1].max
        logger.sleeping(seconds: seconds, reason: REASON_RATE_LIMIT)
        interruptible_sleep(seconds)
      else
        logger.sleeping(seconds: @config.poll_interval, reason: REASON_POLL_INTERVAL)
        interruptible_sleep(@config.poll_interval)
      end
    end

    # sleep(60) would leave a SIGTERM waiting up to a minute for the loop to notice.
    # Waking every second bounds shutdown latency without busy-waiting.
    def interruptible_sleep(seconds)
      deadline = Time.now.utc + seconds
      sleep([1, deadline - Time.now.utc].min) while !@stopping && Time.now.utc < deadline
    end

    # Built per cycle so the client's retry warnings carry this run's id.
    def client_for(logger)
      @injected_client || Github::Client.new(
        url: @config.events_url,
        timeout: @config.request_timeout,
        max_attempts: @config.max_attempts,
        retry_base_delay: @config.retry_base_delay,
        logger: logger
      )
    end
  end
end
