# frozen_string_literal: true

module Ingestion
  class EventProcessor
    # The mutually exclusive results of processing one event.
    module Outcome
      INSERTED = :inserted
      DUPLICATE = :duplicate
      MALFORMED = :malformed
    end

    MISSING_IDENTITY = "Event missing push_id or payload"

    attr_reader :outcome, :event_id, :error_message

    def initialize(event)
      @event = event
      @outcome = nil
      @event_id = event[:id]
      @error_message = nil
    end

    def process
      if missing_identity?
        mark_malformed(MISSING_IDENTITY)
      else
        persist_event
      end
      self
    end

    def inserted?
      outcome == Outcome::INSERTED
    end

    def duplicate?
      outcome == Outcome::DUPLICATE
    end

    def malformed?
      outcome == Outcome::MALFORMED
    end

    private

    def missing_identity?
      payload = @event[:payload]
      payload.blank? || payload[:push_id].blank?
    end

    def mark_malformed(message)
      @outcome = Outcome::MALFORMED
      @error_message = message
    end

    def persist_event
      PushEvent.create!(attributes)
      @outcome = Outcome::INSERTED
    rescue ActiveRecord::RecordNotUnique
      @outcome = Outcome::DUPLICATE
    rescue ActiveRecord::RecordInvalid => e
      mark_malformed(e.message)
    end

    def attributes
      payload = @event[:payload]
      {
        github_event_id: @event[:id],
        push_id: payload[:push_id],
        repo_id: @event[:repo]&.dig(:id),
        actor_id: @event[:actor]&.dig(:id),
        ref: payload[:ref],
        head_sha: payload[:head],
        before_sha: payload[:before],
        event_created_at: @event[:created_at],
        raw_json: @event
      }
    end
  end
end
