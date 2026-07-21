# Changelog

All notable changes to this project are documented here.
Format is a simplified [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are added only after a story branch is merged into `main`.

## [Unreleased]

### STORY-2: Persist Raw and Structured Data (`8a5ef6b`)
- **Added:**
  - Migration `add_structured_columns_to_push_events` — projects `repo_id`, `actor_id`, `ref`, `head_sha`, `before_sha` into queryable columns
  - Indexes on `repo_id` and `actor_id` for efficient filtering
  - Query-by-column capability: `SELECT repo_id, ref, head_sha, before_sha FROM push_events` requires no JSON parsing
- **Changed:**
  - `Ingestion::EventProcessor` now extracts the push attributes from the payload and stores them as structured columns alongside raw JSON
  - Sparse events (missing `repo`, `actor`, or payload fields) are persisted correctly with null values in the projection
- **Fixed:**
  - Events with missing `push_id` are flagged as malformed and skipped, rather than persisted with incomplete identity
- **Technical Notes:**
  - Raw-plus-projection pattern: `raw_json` column retains the verbatim payload for audit/recovery; projected columns satisfy the queryability requirement without requiring JSON parsing
  - `head` and `before` payload fields are stored as `head_sha` and `before_sha` columns because that is what they contain; mapping documented in `context.md`
  - Columns are nullable: projection is derived from the payload, so a partial event persists rather than failing ingestion
  - Acceptance criteria: raw payloads retained ✓, all required fields queryable without JSON parsing ✓, modeling choices documented ✓

### STORY-1: Ingest GitHub Push Events (`f6e9a5e`)
- **Added:**
  - `Github::Client` — thin HTTP wrapper over `GET /events` with User-Agent, timeouts, JSON parsing, and rate-limit header capture
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

### STORY-0: Create boilerplate
- Rails API-only application skeleton with PostgreSQL configured via environment variables
- Docker Compose orchestration: `db`, `api`, `ingest-worker`, `ingest`, `test`
- RSpec with WebMock blocking outbound HTTP, and SimpleCov
- `GET /health` endpoint
