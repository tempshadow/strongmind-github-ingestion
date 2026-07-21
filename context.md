# Project Context

> Describes the repository **as built on this branch**: Stories 1, 2 and 3. Later stories extend
> this document as they land.

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
- Cache-first enrichment of the actor and repository each push event references, governed by the
  remaining rate-limit budget.

Not built yet, by story:
- **Story 4** — retries, backoff, signal handling, structured logging to stdout. The rate-limit
  headers are already read and acted on by enrichment (Section 7); what Story 4 adds is the
  behaviour when the feed request itself is refused, and the operator-facing logging.

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

### `actors`
| Column | Type | Source |
|---|---|---|
| `id` | bigint PK, no sequence | GitHub's actor ID, used verbatim |
| `login` | string, indexed | `login` |
| `url` | string | `url` |
| `avatar_url` | string | `avatar_url` |
| `raw_json` | jsonb, not null | the verbatim user response |
| `fetched_at` | timestamptz | when the row was captured |

### `repositories`
| Column | Type | Source |
|---|---|---|
| `id` | bigint PK, no sequence | GitHub's repository ID, used verbatim |
| `name` | string | `name` |
| `full_name` | string, unique | `full_name` |
| `url` | string | `url` |
| `raw_json` | jsonb, not null | the verbatim repository response |
| `fetched_at` | timestamptz | when the row was captured |

GitHub's IDs are the primary keys, so "have we already fetched this?" is a primary-key hit and the
table *is* the cache. Those ID spaces are stable and never recycled.

`push_events.actor_id` and `repo_id` come from the event payload, not from enrichment, so they are
populated whether or not enrichment ran. They are indexed, and `[repo_id, event_created_at]` is
indexed for repo-over-time queries, but there are **no foreign key constraints**: a push event is
persisted before enrichment, and enrichment may be skipped for budget, so an event legitimately
references an actor or repository row that does not exist yet. `PushEvent belongs_to :actor` and
`belongs_to :repository` are both `optional`, which is the linkage the application relies on.

## 5. Ingestion Flow

1. `bin/ingest` boots Rails and builds a `RunSummary`.
2. `Github::Client#fetch_events` issues one `GET` to the events endpoint.
3. `Ingestion::Runner#record_raw_events` writes a `raw_events` row per event, before filtering.
4. `Ingestion::EventFilter` selects `type == "PushEvent"` and counts what it rejected.
5. `Ingestion::EventProcessor` persists each push event and reports one of `:inserted`,
   `:duplicate`, `:malformed`.
6. `Ingestion::Enricher` resolves the actors and repositories the batch references (Section 6).
7. The runner returns the summary; `--once` exits, `--loop` sleeps `POLL_INTERVAL_SECONDS`.

The rate-limit headers on the feed response are read into the summary before enrichment begins, so
enrichment spends against a measured budget rather than an assumed one.

## 5a. Enrichment Flow

`Ingestion::Enricher` runs after persistence, over the push events of the current batch:

1. Collect `actor.url` and `repo.url` keyed by GitHub ID. A hash keyed by ID means a batch that
   references the same actor thirty times fetches it once. References missing an ID or a URL are
   ignored.
2. Look the ID up in `actors` / `repositories`. A hit costs no HTTP request.
3. On a miss, fetch — but only if `remaining - RATE_LIMIT_RESERVE` is still positive. Otherwise the
   reference is counted as a budget skip and left for a later cycle.
4. Persist the record with its verbatim response and `fetched_at`, then move on. The push event is
   already linked by the `actor_id` / `repo_id` it projected at ingestion.
5. Each enrichment response carries fresh rate-limit headers, which replace the runner's view of
   the budget. The runner never estimates its own usage.

`Github::Client#fetch_events` and `#fetch_resource` share one request path, so the User-Agent,
timeouts, JSON parsing, and rate-limit capture are identical for both.

**Ingestion is never sacrificed to enrichment.** A push event that is persisted but unenriched is a
valid, queryable record; a failed or skipped enrichment is counted, not raised. A single reference
that cannot be fetched — an unreachable resource, or a bot login such as `github-actions[bot]`
whose feed URL contains unescaped brackets — is counted as a failure and does not abort the batch.

**Cached records are never refreshed.** A contributor who changes their login, or a renamed
repository, keeps the values captured at first sight. At 60 requests/hour, re-fetching known
entities directly reduces how many new events we can capture. `fetched_at` records when each row
was captured, so the staleness is visible and a future TTL refresh would have the data it needs.

## 6. Idempotency

Identity comes from upstream, not from us: `github_event_id` and `push_id` both carry unique
indexes, and `raw_events.event_id` does too. Duplicates are handled by attempting the insert and
rescuing `ActiveRecord::RecordNotUnique`, not by a check-then-insert, which would be racy.

There is no checkpoint state to corrupt, so killing the runner mid-cycle and restarting
re-processes at most one page, all of which resolve to no-ops.

An event whose payload has no `push_id` cannot be identified, so it is counted as malformed and
skipped rather than persisted under a fabricated identity.

Enrichment is idempotent for the same reason: `actors` and `repositories` are keyed by GitHub's
IDs, and the enricher only writes on a cache miss, so a re-run over the same batch performs no
writes and issues no requests.

## 6a. Rate Limiting (partial — Story 3 scope)

`Github::RateLimit` parses `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`
from every response. Absent or malformed headers mean the budget is **unknown**, not unlimited;
enrichment proceeds in that case, because the alternative is to stop on a condition we cannot
demonstrate. This is what makes the offline test suite work without inventing header values.

`RATE_LIMIT_RESERVE` (default 10) is the floor. Enrichment stops below it so the next cycle can
always afford at least the feed request itself.

Not built yet: backoff, sleeping until reset, and graceful handling of a 403/429 on the **feed**
request. Today a refused feed request raises out of the runner and exits non-zero. Story 4.

## 7. Configuration

| Variable | Meaning | Default |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection | set per service in Compose |
| `GITHUB_EVENTS_URL` | Events endpoint | `https://api.github.com/events` |
| `POLL_INTERVAL_SECONDS` | Sleep between cycles in `--loop` | `60` |
| `REQUEST_TIMEOUT_SECONDS` | HTTP open/read timeout | `10` |
| `RATE_LIMIT_RESERVE` | Requests held back from enrichment | `10` |
| `RAILS_ENV` | Rails environment | `development` |
| `LOG_LEVEL` | Log verbosity | `info` |

Read through `Ingestion.config`, never from `ENV` at a call site.

## 8. How to Verify

```bash
docker compose up --build          # db, api, ingest-worker
docker compose run --rm ingest     # one cycle, exits 0
docker compose run --rm test       # 86 examples, 0 failures
```

Then check the data:

```sql
SELECT count(*) FROM push_events;
SELECT count(*) FROM raw_events;
SELECT payload->>'type' AS type, count(*) FROM raw_events GROUP BY 1;

SELECT p.push_id, a.login, r.full_name
FROM push_events p
JOIN actors a ON a.id = p.actor_id
JOIN repositories r ON r.id = p.repo_id
LIMIT 5;
```

`raw_events` should be greater than or equal to `push_events`; the difference is the non-push
traffic that was filtered out. Running `ingest` twice within a few minutes should add few or no
new rows, because the feed overlaps heavily between polls, and the second run should enrich
nothing because the actors and repositories are already cached.

If `actors` and `repositories` are empty after a run, check the remaining budget: at or below
`RATE_LIMIT_RESERVE` the enricher skips every reference by design and the run still exits 0.

## 9. Known Limitations

- The public feed exposes roughly the last five minutes of activity and cannot be replayed, so
  gaps are inherent. Completeness is not a goal.
- Unauthenticated requests are capped at 60/hour per IP. Enrichment respects that budget, but the
  feed request does not yet stop gracefully when it is refused (Story 4).
- Enriched actor and repository records are never refreshed, so a renamed repository or a changed
  login keeps its first-seen value.
- A batch can reference more distinct actors and repositories than the budget allows, so some push
  events stay unenriched until a later cycle sees them again. Because the feed is not replayable,
  some may never be enriched.
- Actors whose login contains characters that are invalid in a URL — bot accounts such as
  `github-actions[bot]` — cannot be fetched, and are counted as enrichment failures. Their push
  events are still ingested and still carry `actor_id`.
- Ingestion logs are not routed to stdout yet, so `docker compose logs -f` shows little. Story 4.
