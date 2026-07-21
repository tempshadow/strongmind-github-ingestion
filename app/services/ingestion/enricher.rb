module Ingestion
  class Enricher
    ACTOR_COLUMNS = %i[login url avatar_url].freeze
    REPOSITORY_COLUMNS = %i[name full_name url].freeze

    attr_reader :cache_hits, :fetches, :budget_skips, :failures, :errors, :rate_limit

    def initialize(events, client: nil, rate_limit: nil, config: nil)
      @events = events
      @client = client || Github::Client.new
      @rate_limit = rate_limit || Github::RateLimit.unknown
      @config = config || Config.instance
      @cache_hits = 0
      @fetches = 0
      @budget_skips = 0
      @failures = 0
      @errors = []
    end

    def enrich
      resolve(Actor, references(:actor), ACTOR_COLUMNS)
      resolve(Repository, references(:repo), REPOSITORY_COLUMNS)
      self
    end

    private

    # A hash keyed by GitHub ID, so a batch referencing the same actor 30 times fetches once.
    def references(key)
      @events.each_with_object({}) do |event, urls|
        node = event[key]
        next if node.blank? || node[:id].blank? || node[:url].blank?

        urls[node[:id]] ||= node[:url]
      end
    end

    def resolve(model, urls, columns)
      urls.each do |id, url|
        if model.exists?(id)
          @cache_hits += 1
        elsif affordable?
          fetch_and_store(model, id, url, columns)
        else
          @budget_skips += 1
        end
      end
    end

    # The reserve keeps enough budget for the next cycle's feed request.
    def affordable?
      spendable = @rate_limit.spendable(@config.rate_limit_reserve)
      spendable.nil? || spendable.positive?
    end

    def fetch_and_store(model, id, url, columns)
      response = @client.fetch_resource(url)
      @rate_limit = response[:rate_limit] if response[:rate_limit]&.known?
      store(model, id, response[:body], columns)
      @fetches += 1
    rescue Github::Client::Error => e
      # An unreachable actor or repository must not cost us the events we already persisted.
      @failures += 1
      @errors << "#{model.name}##{id}: #{e.message}"
    end

    def store(model, id, body, columns)
      record = model.find_or_initialize_by(id: id)
      record.assign_attributes(body.slice(*columns))
      record.raw_json = body
      record.fetched_at = Time.current
      record.save!
    end
  end
end
