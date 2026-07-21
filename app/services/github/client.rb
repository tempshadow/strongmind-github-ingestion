require "net/http"
require "json"
require "uri"

module Github
  class Client
    class Error < StandardError; end

    def initialize(url: nil, timeout: nil)
      @url = url || Ingestion.config.events_url
      @timeout = timeout || Ingestion.config.request_timeout
    end

    def fetch_events
      response = make_request(URI(@url))
      parse_response(response)
    end

    private

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
      raise Error, "HTTP error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.empty? ? "[]" : response.body
      {
        status: response.code.to_i,
        body: JSON.parse(body, symbolize_names: true)
      }
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON response: #{e.message}"
    end
  end
end
