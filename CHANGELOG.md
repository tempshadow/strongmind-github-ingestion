# Changelog

All notable changes to this project are documented here.
Format is a simplified [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are added only after a story branch is merged into `main`.

## [Unreleased]

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
