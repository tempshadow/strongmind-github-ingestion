# Changelog

## [Unreleased]

### STORY-0: Create boilerplate
- Set up Rails API-only service with Docker Compose orchestration (PostgreSQL, API server, ingestion worker, test runner)
- Define data model: `push_events` and `raw_events` tables for event storage, `actors` and `repositories` tables for enrichment cache
- Implement ingestion service layer: GitHub API client, rate-limit budget tracking, event filtering, persistence with idempotency, and orchestration runner
- Add `bin/ingest` with `--once` (one-shot) and `--loop` (continuous polling) modes; graceful rate-limit handling with exponential backoff on transient errors
- Write RSpec test suite with WebMock, health check endpoint, and environment-driven configuration
