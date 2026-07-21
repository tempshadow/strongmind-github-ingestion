module Ingestion
  class EventProcessor
    attr_reader :outcome, :event_id, :error_message

    def initialize(event)
      @event = event
      @outcome = nil
      @event_id = event[:id]
      @error_message = nil
    end

    def process
      validate_event
      return self if malformed?

      persist_event
      self
    end

    def inserted?
      outcome == :inserted
    end

    def duplicate?
      outcome == :duplicate
    end

    def malformed?
      outcome == :malformed
    end

    private

    def validate_event
      if @event[:payload].blank? || @event[:payload][:push_id].blank?
        @outcome = :malformed
        @error_message = "Event missing push_id or payload"
        return
      end
    end

    def persist_event
      push_event = PushEvent.new(
        github_event_id: @event[:id],
        push_id: @event[:payload][:push_id],
        repo_id: @event[:repo]&.dig(:id),
        actor_id: @event[:actor]&.dig(:id),
        ref: @event[:payload][:ref],
        head_sha: @event[:payload][:head],
        before_sha: @event[:payload][:before],
        event_created_at: @event[:created_at],
        raw_json: @event
      )

      push_event.save!
      @outcome = :inserted

      # Also save the raw event for the audit trail
      RawEvent.create!(
        event_id: @event[:id],
        payload: @event
      )
    rescue ActiveRecord::RecordNotUnique
      @outcome = :duplicate
    rescue ActiveRecord::RecordInvalid => e
      @outcome = :malformed
      @error_message = e.message
    end
  end
end
