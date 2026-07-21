module Ingestion
  class RunSummary
    attr_accessor :run_id, :fetched_count, :filtered_count, :inserted_count,
                  :duplicate_count, :malformed_count

    def initialize
      @run_id = SecureRandom.hex(8)
      @fetched_count = 0
      @filtered_count = 0
      @inserted_count = 0
      @duplicate_count = 0
      @malformed_count = 0
    end

    def to_s
      "Run #{run_id}: fetched=#{fetched_count} filtered=#{filtered_count} " \
        "inserted=#{inserted_count} duplicates=#{duplicate_count} " \
        "malformed=#{malformed_count}"
    end
  end
end
