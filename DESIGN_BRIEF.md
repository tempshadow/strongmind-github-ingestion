# Design Brief — GitHub Push-Event Ingestion

## How I understood the problem

The public events feed is a lossy, rate-limited, best-effort firehose. It exposes roughly the last
few minutes of public activity, caps unauthenticated callers at 60 requests per hour per IP, and
offers no replay. That framing sets the priorities, in order: **durability** of whatever we manage
to capture, **idempotency** across heavily overlapping polls and unplanned restarts, and **request
economy** — because a single hourly budget spans both the feed poll and enrichment, every avoidable
request is a direct reduction in ingestion coverage. Completeness is explicitly a non-goal: gaps are
inherent to an unauthenticated, polled, non-replayable source, so the design acknowledges them
rather than fighting them. The job is to turn a noisy stream into durable, queryable records that
behave predictably under normal and failure conditions alike.

## Proposed architecture

Rails in API-only mode, a custom ingestion runner (`bin/ingest`), and PostgreSQL as the sole system
of record, wired together by Docker Compose. API-only Rails is the right weight: it supplies
ActiveRecord migrations, connection pooling, and configuration while shedding the view and asset
layers this service has no use for. Compose declares the database, a health-exposing API, a
continuous worker, a one-shot ingest, and a test runner as one reproducible unit a reviewer brings
up with a single command.

The ingestion path is a pipeline of small, single-responsibility, constructor-injected service
objects: an HTTP client whose one request path is shared by the feed and enrichment calls; a
rate-limit header parser; a push-event filter; a per-event processor; an enricher; a cycle object
that runs one pass; and a runner that owns *when* passes happen — once versus continuous loop,
signal handling, and sleep cadence. Persistence uses a **raw-plus-projection** model: every event is
stored verbatim, and the fields analysts actually query — repository and push identifiers, ref, and
the head/before SHAs — are projected into typed, indexed columns alongside it. Enrichment is served
by a **database-backed cache**: actors and repositories are keyed by GitHub's own IDs, so the
durable table *is* the cache and "have we seen this before?" is a primary-key hit.

## Key tradeoffs and assumptions

**A runner, not a job queue.** The workload is a single serialized poll against one shared bucket.
Concurrency would be actively harmful, not merely unnecessary: parallel workers would race for the
same budget and make request accounting non-deterministic, in exchange for parallelism this workload
cannot use.

**The database is the cache.** An in-memory or Redis layer would be a second source of truth for
data we persist anyway, and a cold restart would re-spend the budget rebuilding it. Keeping the
cache in Postgres means restart safety comes for free.

**Cached records are never refreshed.** A rename or a changed login keeps its first-seen value; at
60 requests per hour, re-fetching known entities directly costs new-event coverage. A `fetched_at`
timestamp records the staleness so a future TTL refresh has what it needs — the trade is taken
knowingly, not by omission.

**Ingestion is never sacrificed to enrichment.** A persisted-but-unenriched event is a valid,
queryable record. Enrichment failures and budget skips are counted and logged, never raised.

## How I handled rate limits and durability

**Rate limits.** The `X-RateLimit` headers are the source of truth — usage is measured, never
estimated. A configurable reserve is held back so the next cycle can always afford at least the feed
request; enrichment stops below the reserve and defers those references to a later pass. Within a
batch, actor and repository URLs are deduplicated by ID before any fetch, so a page referencing one
actor thirty times costs a single request. A refused feed request — a 429, or a 403 with the budget
exhausted — is treated as transient: the cycle is abandoned, and in loop mode the runner sleeps
until the reset rather than polling into a wall.

**Durability and idempotency.** Storing each event verbatim alongside its projection means a parsing
mistake is recoverable without re-fetching, and a separate audit row retains every event type, not
just pushes. Identity comes from upstream and is enforced by unique database constraints, so
duplicates are handled by attempting the write and catching the violation rather than a racy
check-then-insert. There is no checkpoint state to corrupt: killing the runner mid-cycle and
restarting re-processes at most one page, all of which resolve to no-ops.

**Resilience and observability.** Transient HTTP failures retry with bounded exponential backoff
plus jitter; permanent ones do not. A cycle that cannot complete is logged and abandoned, and the
process exits zero whenever a cycle completed — including one that did no work because the budget
was spent — so a transient failure never becomes a restart loop. Termination signals finish the
in-flight cycle and exit cleanly. All output is structured `key=value` logging on stdout, each line
carrying a run identifier that correlates one cycle, making the container logs the single pane of
glass. The test suite is hermetic and offline — outbound HTTP is blocked — and covers the judged
behaviours by name: idempotency, malformed input, rate-limit exhaustion, and graceful shutdown,
sitting near 99% line coverage against an enforced 85% floor.

## What I intentionally did not build

- **No background jobs, queues, or Sidekiq** — counterproductive against one shared budget.
- **No UI, analytics, or dashboards** — the projected columns leave analytics a later SQL concern.
- **No object storage** — resource URLs are persisted; the bytes are not, and `jsonb` suffices at
  this volume.
- **No cache invalidation or TTL refresh** — the staleness trade is taken deliberately.
- **No authentication** — no outbound token (prohibited), and none inbound on an internal service.
- **No CI pipeline** — the suite runs in Docker under lint and coverage gates; wiring CI is a
  deployment concern beyond this exercise.
- **No backfill or replay** — the feed has no history, so completeness would need a different source.
