# Changelog

All notable changes to this project are documented here.
Format is a simplified [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are added only after a story branch is merged into `main`.

## [Unreleased]

### STORY-4: Operability and Observability (commit `bdb6e6d`)
- **Added:**
  - `Ingestion::RunLogger` — structured `key=value` logging to stdout, every line carrying the `run_id` that correlates one cycle
  - Error classification in `Github::Client`: `TransientError` (timeouts, resets, 5xx, 429, rate-limited 403) and `PermanentError` (other 4xx, unparseable bodies, malformed URLs)
  - Bounded retries with exponential backoff plus jitter, capped by `MAX_ATTEMPTS`
  - `SIGTERM`/`SIGINT` handling: the in-flight cycle finishes, `ingestion.shutdown` is logged, and the process exits 0
  - Config: `MAX_ATTEMPTS` (default 3), `RETRY_BASE_DELAY_SECONDS` (default 1)
- **Changed:**
  - Rails logs to stdout unbuffered, so `docker compose logs -f` is the operator's single pane
  - `Ingestion::Runner` logs the full lifecycle and abandons a failed cycle instead of raising
- **Fixed:**
  - The poll sleep now wakes every second to check the stop flag. A plain `sleep(poll_interval)` left Docker waiting out its stop timeout and escalating to `SIGKILL`, which surfaced as exit 137; a regression spec covers it.
- **Technical Notes:**
  - Only transient errors are retried; jitter matters because every retry is driven by the same upstream, so unjittered delays would resynchronise
  - Exit 0 means the cycle completed, including one that did no work because the budget was spent. Non-zero is reserved for conditions a restart could fix, which is what makes `restart: on-failure:3` safe
  - Acceptance criteria: logs show ingestion behaviour, successful processing, and failures/retries ✓, malformed data handled gracefully ✓, no crash-loop on transient failures ✓
  - Stories 1–3 criteria still met; see the verification matrix in `context.md`

### STORY-3: Enrich Push Events (commit `2af86db`)
- **Added:**
  - `Ingestion::Enricher` — resolves actor and repository URLs in a cache-first pattern, governed by rate-limit budget
  - `Github::RateLimit` — parses `X-RateLimit-*` headers and tracks spendable budget above the reserve floor
  - `Actor` and `Repository` models with GitHub IDs as primary keys, avoiding redundant fetches
  - Migrations: `create_actors`, `create_repositories`, `add_enrichment_indexes_to_push_events`
  - Integration tests verifying cache hits, budget enforcement, and unenriched persistence
- **Changed:**
  - `Github::Client#fetch_resource` — added for enrichment requests; reuses User-Agent, timeouts, JSON parsing, and rate-limit capture
  - `Ingestion::Runner` — orchestrates enrichment after persistence; no fetches sacrifice completed ingestion
  - `RunSummary` — added `enrichment_hits`, `enrichment_fetches`, `enrichment_skips`, `enrichment_failures` counters and `rate_limit` field
- **Technical Notes:**
  - Cache-first strategy: the `actors` and `repositories` tables are the cache; a hit by GitHub ID costs no HTTP request
  - Batch deduplication: multiple references to the same actor/repo in one batch trigger only one fetch
  - Budget-aware: enrichment stops when spendable budget (remaining minus reserve) falls to zero; unmatched references are counted as skips and left for a later cycle
  - No cascade between ingestion and enrichment: unenriched push events are valid, queryable records; failed enrichment is logged, not raised
  - Acceptance criteria: URLs extracted from payload ✓, data persisted durably ✓, repeated fetches avoided via cache ✓; approach documented in `context.md` (design brief still outstanding)
  - Story 1 & 2 criteria still met: events filtered and persisted ✓, raw payloads retained ✓, fields queryable ✓

### STORY-2: Persist Raw and Structured Data (commit `8910f57`)
- **Added:**
  - Migration `add_structured_columns_to_push_events` — projects `repo_id`, `actor_id`, `ref`, `head_sha`, `before_sha` into queryable columns
  - Indexes on `repo_id` and `actor_id` for efficient filtering
  - Query-by-column capability: `SELECT repo_id, ref, head_sha, before_sha FROM push_events` requires no JSON parsing
- **Changed:**
  - `Ingestion::EventProcessor` now extracts the push attributes from the payload and stores them as structured columns alongside raw JSON
  - Sparse events (missing `repo`, `actor`, or payload fields) are persisted correctly with null values in the projection
- **Technical Notes:**
  - Raw-plus-projection pattern: `raw_json` column retains the verbatim payload for audit/recovery; projected columns satisfy the queryability requirement without requiring JSON parsing
  - `head` and `before` payload fields are stored as `head_sha` and `before_sha` columns because that is what they contain; mapping documented in `context.md`
  - Columns are nullable: projection is derived from the payload, so a partial event persists rather than failing ingestion
  - Acceptance criteria: raw payloads retained ✓, all required fields queryable without JSON parsing ✓, modeling choices documented ✓

### STORY-1: Ingest GitHub Push Events (commit `56af955`)
- **Added:**
  - `Github::Client` — thin HTTP wrapper over `GET /events` with User-Agent, timeouts, and JSON parsing
  - `Ingestion::EventFilter` — filters to `PushEvent` type only, counts rejected events
  - `Ingestion::EventProcessor` — persists events idempotently in separate transactions; marks malformed events (missing `push_id`) without persisting
  - `Ingestion::Runner` — orchestrates one cycle and returns `RunSummary` with counts
  - `bin/ingest` — executable entrypoint with `--once` and `--loop` modes
  - `PushEvent` model with unique indexes on `github_event_id` and `push_id`
  - `RawEvent` model capturing all event types for audit trail
  - Migrations: `create_push_events`, `create_raw_events`
  - Integration tests verifying idempotency, filtering, and unique constraint enforcement
- **Technical Notes:**
  - Idempotency enforced at the database level via unique constraints, not application logic
  - Re-running the same events results in zero new inserts; duplicates are counted and skipped gracefully
  - Raw JSON payloads retained verbatim alongside the table for audit and recovery
  - Acceptance criteria: events are fetched, filtered to PushEvent only, persisted durably, uniquely identified, and repeatable

### STORY-0: Create boilerplate (commit `c537030`)
- Rails API-only application skeleton with PostgreSQL configured via environment variables
- Docker Compose orchestration: `db`, `api`, `ingest-worker`, `ingest`, `test`
- RSpec with WebMock blocking outbound HTTP, and SimpleCov
- `GET /health` endpoint
