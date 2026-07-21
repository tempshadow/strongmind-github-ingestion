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

      # The audit trail covers every event type, so it is written before filtering.
      record_raw_events(response[:body])

      filtered = EventFilter.new(response[:body]).filter
      summary.filtered_count = filtered.push_events.length

      process_events(filtered.push_events, summary)
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
