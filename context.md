# Project Context

> Describes the repository **as built on this branch**: Stories 1 and 2. Later stories extend this
> document as they land.

## 1. Purpose

An internal service that ingests GitHub `PushEvent` activity from the public events API so it can
be analysed later. It runs unattended and stores events durably in PostgreSQL.

## 2. Scope on This Branch

Built:
- Polling the public events feed, unauthenticated.
- Filtering to `PushEvent`; every other type is counted and skipped.
- Durable persistence of each push event with its raw payload.
- An audit trail of every event seen, regardless of type.
- Idempotent re-runs.
- Projection of the key push attributes into queryable columns alongside the raw payload.

Not built yet, by story:
- **Story 3** — actor and repository enrichment.
- **Story 4** — rate-limit tracking, retries, backoff, structured logging to stdout.

Not built at all: UI, analytics, dashboards, background jobs, queues, object storage,
authentication.

## 3. Architecture

Rails in API-only mode with a plain Ruby runner rather than a job queue. The workload is a single
serialized poll against one shared rate-limit budget, so concurrency would only cause contention.

Docker Compose services:

| Service | Role |
|---|---|
| `db` | PostgreSQL 16, the only system of record. Named volume `pgdata`. |
| `api` | Rails API. Owns the schema; exposes `GET /health`. |
| `ingest-worker` | `bin/ingest --loop`, starts with `docker compose up`. |
| `ingest` | `bin/ingest --once`, profile `manual`, for `docker compose run --rm ingest`. |
| `test` | RSpec, profile `manual`, for `docker compose run --rm test`. |

All four application services share one image, `strongmind-github-ingestion:latest`, so they
cannot drift apart. `Gemfile.lock` is a committed build input.

## 4. Data Model

### `push_events`
| Column | Type | Source |
|---|---|---|
| `id` | bigserial PK | internal surrogate key |
| `github_event_id` | string, unique | envelope `id` |
| `push_id` | bigint, unique | `payload.push_id` |
| `repo_id` | bigint, indexed | `repo.id` |
| `actor_id` | bigint, indexed | `actor.id` |
| `ref` | string | `payload.ref` |
| `head_sha` | string | `payload.head` |
| `before_sha` | string | `payload.before` |
| `event_created_at` | timestamptz | upstream `created_at` |
| `raw_json` | jsonb, not null | the verbatim event |

`head` and `before` are stored as `head_sha` / `before_sha` because that is what they contain and
because a bare `before` column reads poorly in SQL. The projected columns are nullable: they are
derived from the payload, so a sparse event still persists rather than failing ingestion.

### `raw_events`
| Column | Type | Source |
|---|---|---|
| `id` | bigserial PK | internal surrogate key |
| `event_id` | string, unique | envelope `id` |
| `payload` | jsonb, not null | the verbatim event, any type |

Both tables keep the raw payload so a parsing mistake can be recovered from without re-fetching.
`raw_events` covers every event type; `push_events` covers only pushes.

## 5. Ingestion Flow

1. `bin/ingest` boots Rails and builds a `RunSummary`.
2. `Github::Client#fetch_events` issues one `GET` to the events endpoint.
3. `Ingestion::Runner#record_raw_events` writes a `raw_events` row per event, before filtering.
4. `Ingestion::EventFilter` selects `type == "PushEvent"` and counts what it rejected.
5. `Ingestion::EventProcessor` persists each push event and reports one of `:inserted`,
   `:duplicate`, `:malformed`.
6. The runner returns the summary; `--once` exits, `--loop` sleeps `POLL_INTERVAL_SECONDS`.

## 6. Idempotency

Identity comes from upstream, not from us: `github_event_id` and `push_id` both carry unique
indexes, and `raw_events.event_id` does too. Duplicates are handled by attempting the insert and
rescuing `ActiveRecord::RecordNotUnique`, not by a check-then-insert, which would be racy.

There is no checkpoint state to corrupt, so killing the runner mid-cycle and restarting
re-processes at most one page, all of which resolve to no-ops.

An event whose payload has no `push_id` cannot be identified, so it is counted as malformed and
skipped rather than persisted under a fabricated identity.

## 7. Configuration

| Variable | Meaning | Default |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection | set per service in Compose |
| `GITHUB_EVENTS_URL` | Events endpoint | `https://api.github.com/events` |
| `POLL_INTERVAL_SECONDS` | Sleep between cycles in `--loop` | `60` |
| `REQUEST_TIMEOUT_SECONDS` | HTTP open/read timeout | `10` |
| `RAILS_ENV` | Rails environment | `development` |
| `LOG_LEVEL` | Log verbosity | `info` |

Read through `Ingestion.config`, never from `ENV` at a call site.

## 8. How to Verify

```bash
docker compose up --build          # db, api, ingest-worker
docker compose run --rm ingest     # one cycle, exits 0
docker compose run --rm test       # 43 examples, 0 failures
```

Then check the data:

```sql
SELECT count(*) FROM push_events;
SELECT count(*) FROM raw_events;
SELECT payload->>'type' AS type, count(*) FROM raw_events GROUP BY 1;
```

`raw_events` should be greater than or equal to `push_events`; the difference is the non-push
traffic that was filtered out. Running `ingest` twice within a few minutes should add few or no
new rows, because the feed overlaps heavily between polls.

## 9. Known Limitations

- The public feed exposes roughly the last five minutes of activity and cannot be replayed, so
  gaps are inherent. Completeness is not a goal.
- Unauthenticated requests are capped at 60/hour per IP; that budget is not tracked yet (Story 4).
- Ingestion logs are not routed to stdout yet, so `docker compose logs -f` shows little. Story 4.
