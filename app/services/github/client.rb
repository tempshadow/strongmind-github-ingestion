require "net/http"
require "json"
require "uri"

module Github
  class Client
    class Error < StandardError; end
    class TransientError < Error; end
    class PermanentError < Error; end

    def initialize(url = nil, timeout: 10)
      @url = url || ENV["GITHUB_EVENTS_URL"] || "https://api.github.com/events"
      @timeout = timeout
      @etag = nil
    end

    def fetch_events
      uri = URI(@url)
      response = make_request(uri)
      parse_response(response)
    end

    def fetch_resource(url)
      uri = URI(url)
      response = make_request(uri)
      parse_response(response)
    end

    private

    def make_request(uri, max_retries: 3)
      retries = 0
      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = "StrongMind-GitHub-Ingestion/1.0"
        request["Accept"] = "application/vnd.github.v3+json"
        request["If-None-Match"] = @etag if @etag

        http.request(request)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
        retries += 1
        if retries < max_retries
          sleep(2 ** retries)
          retry
        else
          raise TransientError, "Network error after #{max_retries} attempts: #{e.message}"
        end
      end
    end

    def parse_response(response)
      rate_limit = {
        remaining: response["X-RateLimit-Remaining"]&.to_i,
        limit: response["X-RateLimit-Limit"]&.to_i,
        reset: response["X-RateLimit-Reset"]&.to_i
      }

      case response
      when Net::HTTPSuccess
        @etag = response["ETag"]
        body = response.body.empty? ? "[]" : response.body
        {
          status: response.code.to_i,
          body: JSON.parse(body, symbolize_names: true),
          rate_limit: rate_limit
        }
      when Net::HTTPNotModified
        {
          status: 304,
          body: [],
          rate_limit: rate_limit
        }
      when Net::HTTPClientError, Net::HTTPServerError
        if response.code.to_i.in?([403, 429])
          raise TransientError, "Rate limit or temporary error: #{response.code}"
        else
          raise PermanentError, "Permanent HTTP error: #{response.code}"
        end
      else
        raise PermanentError, "Unexpected response: #{response.class}"
      end
    rescue JSON::ParserError => e
      raise PermanentError, "Invalid JSON response: #{e.message}"
    end
  end
end
