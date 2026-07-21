# Project Context

## 1. Purpose
StrongMind ingests GitHub `PushEvent` data from the public GitHub Events API to analyse repository usage and contributor behaviour over time. The deliverable is a small internal service that polls the public events feed, enriches events with actor and repository metadata, and stores everything durably in PostgreSQL with structured logging for operational visibility.

## 2. Scope and Non-Goals
**Built:** Rails API-only service; Docker Compose orchestration; `bin/ingest` runner; event filtering and projection; actor/repository enrichment with database-backed caching; structured logging with run correlation; graceful rate-limit and error handling.

**Intentionally not built:** UI, analytics/aggregation, dashboards, background jobs, queues, Redis, distributed ingestion, object storage, authentication, cache invalidation/TTL refresh, backfill or replay. These are documented in the implementation plan (Section 10) with reasoning.

## 3. Architecture
**Components:**
- `db` — PostgreSQL 16 with named volume, single system of record
- `api` — Rails API-only container; runs migrations; schema owner; inspection surface via `rails console`
- `ingest-worker` — same image, runs `bin/ingest --loop` continuously on startup
- `ingest` — same image, runs `bin/ingest --once` via `docker compose run --rm`; deterministic one-shot ingestion
- `test` — same image, runs the RSpec suite against a test database

All services share the same Dockerfile and codebase. Configuration is environment-driven; no hard-coded credentials or localhost defaults.

## 4. Data Model

### `push_events`
| Column | Type | Notes |
|---|---|---|
| `id` | bigserial PK | internal surrogate key |
| `github_event_id` | string, unique | envelope `id` from the events feed |
| `push_id` | bigint, unique | `payload.push_id`; business identity of the push |
| `repo_id` | bigint | GitHub repository ID, from `repo.id` in payload |
| `actor_id` | bigint | GitHub actor ID, from `actor.id` in payload |
| `ref` | string | e.g. `refs/heads/main` |
| `head_sha` | string | `payload.head` |
| `before_sha` | string | `payload.before` |
| `event_created_at` | timestamptz | upstream `created_at`, distinct from our `created_at` |
| `raw_json` | jsonb | verbatim event envelope, audit trail |
| `created_at` | timestamptz | when we ingested this row |

Indexes on `(repo_id, event_created_at)`, `(actor_id, event_created_at)`, `event_created_at`.

### `raw_events`
| Column | Type | Notes |
|---|---|---|
| `id` | bigserial PK | |
| `event_id` | string, unique | envelope `id` |
| `payload` | jsonb | verbatim, all event types received |
| `created_at` | timestamptz | when we saw this |

Stores the complete audit trail of what the feed exposed, including non-`PushEvent` types.

### `actors`
| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | GitHub's actor ID, used directly as PK; no sequence |
| `login` | string | login name |
| `url` | string | API URL used to fetch |
| `avatar_url` | string | |
| `raw_json` | jsonb | verbatim response from GitHub API |
| `fetched_at` | timestamptz | when enrichment last succeeded |
| `created_at` | timestamptz | when we first cached this |

Index on `login`.

### `repositories`
| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | GitHub's repository ID, used directly as PK; no sequence |
| `name` | string | repository name |
| `full_name` | string | owner/repo |
| `url` | string | API URL used to fetch |
| `raw_json` | jsonb | verbatim response from GitHub API |
| `fetched_at` | timestamptz | when enrichment last succeeded |
| `created_at` | timestamptz | when we first cached this |

Unique index on `full_name`.

### Modelling Notes
- **`head_sha` / `before_sha` naming:** The payload contains fields `head` and `before`; we store them as `head_sha` and `before_sha` to clarify the content and for readability in SQL/ActiveRecord.
- **GitHub IDs as primary keys:** Using upstream IDs as PKs for `actors` and `repositories` makes cache lookups primary-key hits and answers "have we fetched this?" for free. `push_events` carries `repo_id` / `actor_id` as plain GitHub IDs that double as foreign keys (or are indexed if soft FK is preferred).
- **Raw-plus-projection:** Every table stores the verbatim upstream JSON *and* the columns we query on. Raw is the audit record and recovery path; projected columns are the contract for analysts.

## 5. Ingestion Flow
1. Runner starts, boots Rails, verifies DB connectivity, reads config from environment
2. Log run start with run ID, mode, poll interval
3. Fetch events: one `GET /events` request
4. Check rate-limit headers: `X-RateLimit-Remaining`, `X-RateLimit-Reset` — record before further work
5. Filter to `PushEvent` only; count and discard others (or record in `raw_events`)
6. Persist raw + structured data: one transaction per event, not per batch — malformed event doesn't roll back the cycle
7. Enrich actor + repository: cache-first, see Section 6
8. Log summary: fetched, filtered, inserted, duplicates skipped, enriched, cache hits, errors, remaining budget
9. Exit cleanly: code 0 on completed cycle (including cycles that did no work due to budget exhaustion); non-zero reserved for misconfiguration

## 6. Enrichment Flow
1. Extract `actor.url` and `repo.url` from event payload
2. Check the database cache: `Actor.find_by(id:)` / `Repository.find_by(id:)` — primary-key lookups
3. Fetch only on miss: one request per previously unseen actor or repository
4. Persist the row with raw JSON
5. Link to the push event
6. Log outcome: cache hit, fetched, or skipped due to budget

**Why the database is the cache:** No in-memory or Redis cache — that would be a second source of truth for data we must persist anyway. The persisted table survives restarts, so it matters more than lookup latency here. Because `actors` and `repositories` are keyed by GitHub's IDs, the persisted table *is* the cache.

**Fan-out control:** A single events page can reference up to 30 distinct actors and repositories. Fetching all naively costs up to 60 requests — the entire hourly budget — for one page. We therefore deduplicate URLs within the batch, consult cache first, and stop enriching when the remaining budget falls below the reserve. Unenriched events are correct, queryable records awaiting a later pass. Ingestion is never sacrificed to enrichment.

**Staleness trade-off:** Cached actor and repository records are never refreshed. A login change or repository rename will show the original values. This is the right trade at 60 req/hr — re-fetching known entities reduces how many new events we capture. `fetched_at` records provenance so future TTL-based refresh has the data it needs.

## 7. Rate Limiting
- Track `X-RateLimit-Remaining` and `X-RateLimit-Reset` from every response — headers are the source of truth
- Reserve a floor: below a configured threshold (default 10), enrichment stops but ingestion of fetched events completes
- Back off: as budget nears exhaustion, extend the poll interval rather than continuing at full cadence
- Stop gracefully: on remaining == 0 or HTTP 403/429, log reset time, sleep until reset (loop mode) or exit 0 (one-shot)
- Avoid crash loops: transient errors (timeouts, 5xx, connection resets) are caught, logged, retried with bounded exponential backoff and jitter; runs that cannot progress exit cleanly
- Avoid wasteful polling: the default poll interval is set so continuous runs stay inside the hourly budget by construction

**The stance:** The rate limit is a budget to be spent deliberately, not an error to be handled.

## 8. Idempotency and Restart Safety
- Unique constraints in the database on `push_events.push_id` and `push_events.github_event_id`; database is the enforcement point
- Skip duplicates by inserting and handling uniqueness violation (or `INSERT ... ON CONFLICT DO NOTHING`), not check-then-insert
- Log "duplicate ignored" at debug; per-cycle count at info — overlap is normal and expected
- Because identity is upstream-derived and enforced by constraints, the runner has no checkpoint state to corrupt. A mid-cycle kill and restart re-processes at most one page; all re-inserted events resolve to no-ops
- Actor and repository upserts are keyed on GitHub IDs and are likewise idempotent
- Bounded growth: `push_events` grows only with genuinely new pushes; enrichment tables converge on distinct actors/repos seen

## 9. Operational Behaviour
All logs go to stdout/stderr so `docker compose logs -f` is the operator's single pane.

Every run emits, in order:
- Ingestion start — run ID, mode, interval, target endpoint
- Event counts — fetched, PushEvent filtered, inserted, duplicates skipped, malformed
- Rate-limit status — remaining, limit, reset time, action taken
- Enrichment steps — cache hits, fetches performed, skipped-for-budget
- Errors + retries — the failing operation, attempt number, backoff applied, final outcome; errors carry the event ID
- Graceful shutdown — summary line and exit code

One structured line per meaningful event. Stable `run_id` correlates every line of a cycle. `LOG_LEVEL` is configurable; default is `info`. At info level, a reviewer sees the lifecycle and counts but not per-event chatter. Info-level output is human-readable at a glance.

Exit code 0 means "the cycle completed", including cycles that did no work because the budget was spent. Non-zero is reserved for genuine misconfiguration (the only condition a restart could plausibly fix).

## 10. Configuration
Environment variables, read at boot:

| Variable | Meaning | Default | Effect |
|---|---|---|---|
| `DATABASE_URL` or `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` | PostgreSQL connection | `localhost:5432`, database `strongmind_ingestion_dev` | Configures `config/database.yml` |
| `RAILS_ENV` | Rails environment | `development` | Application mode |
| `LOG_LEVEL` | Logging level | `info` | Structured logger threshold |
| `GITHUB_EVENTS_URL` | GitHub events endpoint | `https://api.github.com/events` | Polling target |
| `POLL_INTERVAL_SECONDS` | Seconds between polls (loop mode) | `60` | Backoff basis |
| `RATE_LIMIT_RESERVE` | Minimum requests to preserve | `10` | Threshold below which enrichment stops |
| `REQUEST_TIMEOUT_SECONDS` | HTTP connect/read timeout | `10` | Network wait limit |
| `MAX_RETRIES` | Max attempts on transient failure | `3` | Retry ceiling |
| `RETRY_BASE_DELAY_SECONDS` | Starting backoff delay | `1` | Exponential backoff base |

No hard-coded credentials or localhost defaults that only work outside Docker.

## 11. How to Verify
**Initial setup:**
```bash
docker compose up --build
docker compose run --rm test
```

**Continuous ingestion:**
```bash
docker compose logs -f ingest-worker
```

**One-shot ingest:**
```bash
docker compose run --rm ingest
```

**Check data:**
```bash
docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
  -c "SELECT COUNT(*) FROM push_events;"
docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
  -c "SELECT COUNT(*) FROM actors;"
```

**Inspect with rails console:**
```bash
docker compose exec api rails console
# Then: PushEvent.count, Actor.count, etc.
```

After running, expect to see:
- Ingestion start log with run ID
- Event count summary (fetched, filtered, inserted)
- Rate-limit remaining reported
- `push_events` table populated with raw JSON and structured fields
- `raw_events` table populated with all event types seen
- Logs show cache hits on second run (no enrichment requests)

## 12. Known Limitations
- **Feed gaps:** The public events feed exposes ~5 minutes of activity. We poll it; gaps are inherent and not a sign of failure.
- **Enrichment staleness:** Cached actor/repository records are never refreshed. Login changes, repository renames, and profile updates are not reflected. `fetched_at` documents when the record was captured.
- **Single-runner throughput ceiling:** Only one ingestion process at a time. The rate limit is the binding constraint; this ceiling is far above it today.
- **Unauthenticated budget:** 60 requests/hour shared between feed and enrichment. Scaling to higher throughput requires an authenticated token (outside scope).
- **No replay:** The public feed offers no history. A system requiring completeness would need GH Archive (separate implementation).
