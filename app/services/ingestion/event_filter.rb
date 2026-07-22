# frozen_string_literal: true

module Ingestion
  class EventFilter
    attr_reader :push_events, :rejected_count

    def initialize(events)
      @events = events
      @push_events = []
      @rejected_count = 0
    end

    def filter
      @events.each do |event|
        if event[:type] == Github::EventType::PUSH
          @push_events << event
        else
          @rejected_count += 1
        end
      end

      self
    end
  end
end
