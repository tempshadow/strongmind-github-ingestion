module Ingestion
  class EventFilter
    def initialize(events)
      @events = events
      @push_events = []
      @rejected_count = 0
    end

    def filter
      @events.each do |event|
        if event[:type] == "PushEvent"
          @push_events << event
        else
          @rejected_count += 1
        end
      end

      self
    end

    def push_events
      @push_events
    end

    def rejected_count
      @rejected_count
    end
  end
end
