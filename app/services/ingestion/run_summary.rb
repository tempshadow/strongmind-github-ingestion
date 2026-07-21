module Ingestion
  class RunSummary
    attr_accessor :run_id, :fetched_count, :filtered_count, :inserted_count,
                  :duplicate_count, :malformed_count, :enrichment_hits,
                  :enrichment_fetches, :enrichment_skips, :enrichment_failures,
                  :rate_limit

    def initialize
      @run_id = SecureRandom.hex(8)
      @fetched_count = 0
      @filtered_count = 0
      @inserted_count = 0
      @duplicate_count = 0
      @malformed_count = 0
      @enrichment_hits = 0
      @enrichment_fetches = 0
      @enrichment_skips = 0
      @enrichment_failures = 0
      @rate_limit = Github::RateLimit.unknown
    end

    def to_s
      "Run #{run_id}: fetched=#{fetched_count} filtered=#{filtered_count} " \
        "inserted=#{inserted_count} duplicates=#{duplicate_count} " \
        "malformed=#{malformed_count} " \
        "enrichment[hits=#{enrichment_hits} fetches=#{enrichment_fetches} " \
        "skipped=#{enrichment_skips} failed=#{enrichment_failures}] " \
        "rate_limit[#{rate_limit}]"
    end
  end
end
