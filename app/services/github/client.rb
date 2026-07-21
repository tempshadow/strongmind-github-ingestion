require "net/http"
require "json"
require "uri"

module Github
  class Client
    class Error < StandardError; end

    # Worth another attempt: timeouts, resets, 5xx, and rate-limit rejections.
    class TransientError < Error
      attr_reader :rate_limit

      def initialize(message, rate_limit: nil)
        super(message)
        @rate_limit = rate_limit
      end
    end

    # Retrying will not help: 4xx other than 429, and unparseable responses.
    class PermanentError < Error; end

    RETRYABLE_EXCEPTIONS = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Net::OpenTimeout, Net::ReadTimeout, IOError, SocketError, Timeout::Error
    ].freeze

    def initialize(url: nil, timeout: nil, config: nil, logger: nil)
      @config = config || Ingestion.config
      @url = url || @config.events_url
      @timeout = timeout || @config.request_timeout
      @logger = logger
    end

    def fetch_events
      get(@url)
    end

    def fetch_resource(url)
      get(url)
    end

    private

    def get(url)
      uri = parse_uri(url)
      with_retries(url) { parse_response(make_request(uri)) }
    end

    # Bot logins such as `github-actions[bot]` reach us as unescaped URLs.
    def parse_uri(url)
      URI(url)
    rescue URI::InvalidURIError => e
      raise PermanentError, "Invalid URL: #{e.message}"
    end

    # Bounded exponential backoff with jitter. Jitter matters because every retry
    # here is driven by the same upstream, so unjittered delays would resynchronise.
    def with_retries(url)
      attempt = 0

      begin
        attempt += 1
        yield
      rescue *RETRYABLE_EXCEPTIONS => e
        raise TransientError, "#{e.class}: #{e.message}" if attempt >= @config.max_attempts

        backoff(attempt, url, e.class.name)
        retry
      rescue TransientError => e
        raise if attempt >= @config.max_attempts

        backoff(attempt, url, e.message)
        retry
      end
    end

    def backoff(attempt, url, reason)
      delay = @config.retry_base_delay * (2**(attempt - 1))
      delay += rand * @config.retry_base_delay
      @logger&.retrying(url: url, attempt: attempt, max: @config.max_attempts,
                        delay: delay.round(2), reason: reason)
      sleep(delay)
    end

    def make_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      request = Net::HTTP::Get.new(uri.request_uri)
      # GitHub rejects requests without a User-Agent.
      request["User-Agent"] = "StrongMind-GitHub-Ingestion/1.0"
      request["Accept"] = "application/vnd.github.v3+json"

      http.request(request)
    end

    def parse_response(response)
      rate_limit = RateLimit.from_response(response)
      classify(response, rate_limit) unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s.empty? ? "[]" : response.body
      {
        status: response.code.to_i,
        body: JSON.parse(body, symbolize_names: true),
        rate_limit: rate_limit
      }
    rescue JSON::ParserError => e
      raise PermanentError, "Invalid JSON response: #{e.message}"
    end

    def classify(response, rate_limit)
      code = response.code.to_i

      # An unauthenticated 403 from GitHub is nearly always the rate limiter.
      if code == 429 || (code == 403 && rate_limit.exhausted?)
        raise TransientError.new("Rate limited: HTTP #{code}", rate_limit: rate_limit)
      elsif code >= 500
        raise TransientError.new("Upstream error: HTTP #{code}", rate_limit: rate_limit)
      else
        raise PermanentError, "HTTP error: #{code}"
      end
    end
  end
end
