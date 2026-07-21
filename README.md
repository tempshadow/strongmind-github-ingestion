# StrongMind GitHub Ingestion

A Rails-based service that ingests `PushEvent` data from the public GitHub Events API and stores everything durably in PostgreSQL.

## Quick Start

### Prerequisites
- Docker and Docker Compose

### Build and Start
```bash
docker compose up --build
```

This starts:
- `db` — PostgreSQL 16
- `api` — Rails API server on port 3000
- `ingest-worker` — Continuous ingestion (one cycle every 60 seconds)

### Run Tests
```bash
docker compose run --rm test
```

### One-Shot Ingestion
```bash
docker compose run --rm ingest
```

### Check Data
```bash
docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
  -c "SELECT COUNT(*) FROM push_events;"

docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
  -c "SELECT COUNT(*) FROM raw_events;"
```

### Rails Console
```bash
docker compose exec api rails console
# Then: PushEvent.count, RawEvent.count
```

## How to Verify It's Working

After `docker compose up`, wait 30 seconds and then check:

1. **Logs show ingestion running:**
   ```bash
   docker compose logs -f ingest-worker
   ```
   Every line carries a `run_id` correlating one cycle. Expect this sequence:
   ```
   run_id=2ca37a73 event=ingestion.started mode=once
   run_id=2ca37a73 event=ingestion.fetched events=30 rate_limit="remaining=59/60 reset_at=..."
   run_id=2ca37a73 event=ingestion.filtered push_events=29 rejected=1
   run_id=2ca37a73 event=ingestion.processed inserted=29 duplicates=0 malformed=0
   run_id=2ca37a73 event=ingestion.enriched cache_hits=0 fetches=49 skipped=7 failed=1
   run_id=2ca37a73 event=ingestion.finished result="Run 2ca37a73: fetched=30 ..."
   run_id=2ca37a73 event=ingestion.sleeping seconds=60 reason="poll interval"
   ```
   On the second cycle `duplicates` should rise and `inserted` fall to 0, and `cache_hits`
   should replace `fetches` — that is idempotency and the enrichment cache working.
   `skipped` is enrichment yielding at the rate-limit reserve, which is expected on a
   60 requests/hour budget.

2. **Data is persisted:**
   ```bash
   docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
     -c "SELECT repo_id, push_id, ref, head_sha, before_sha FROM push_events LIMIT 5;"
   ```
   You should see the key push attributes as columns, with no JSON parsing. `raw_events` will have at least as many rows, since it records every event type.

3. **Actors and repositories are enriched:**
   ```bash
   docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
     -c "SELECT p.push_id, a.login, r.full_name FROM push_events p
         JOIN actors a ON a.id = p.actor_id
         JOIN repositories r ON r.id = p.repo_id LIMIT 5;"
   ```
   Running `ingest` a second time over the same actors issues no enrichment requests — they
   are served from these tables. If the remaining hourly budget is at or below
   `RATE_LIMIT_RESERVE`, enrichment is skipped and the push events land unenriched; that is
   expected, and the run still exits 0.

4. **Tests pass:**
   ```bash
   docker compose run --rm test
   ```
   Should exit with exit code 0.

## Architecture

See [context.md](context.md) for full documentation on:
- Data model (push_events with structured projection, raw_events)
- Ingestion flow (polling, filtering, persistence)
- Idempotency (duplicate detection via unique constraints)
- Configuration and verification steps

## Configuration

Environment variables (see `.env.example`):
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` — PostgreSQL connection
- `RAILS_ENV` — Rails environment (development, test, production)
- `LOG_LEVEL` — Log verbosity (default: info)
- `GITHUB_EVENTS_URL` — GitHub events endpoint (default: https://api.github.com/events)
- `POLL_INTERVAL_SECONDS` — Seconds between polls in loop mode (default: 60)
- `REQUEST_TIMEOUT_SECONDS` — HTTP timeout (default: 10)
- `RATE_LIMIT_RESERVE` — Requests held back from enrichment (default: 10)
- `MAX_ATTEMPTS` — Total attempts per HTTP request before giving up (default: 3)
- `RETRY_BASE_DELAY_SECONDS` — Backoff base; doubles each attempt, plus jitter (default: 1)

## Operational Behaviour

- **Exit codes.** `bin/ingest` exits 0 whenever a cycle completed, including one that did no work
  because the rate-limit budget was spent. Non-zero is reserved for misconfiguration — the only
  condition a restart could fix — which is why `ingest-worker` safely carries `restart: on-failure:3`.
- **Transient failures.** Timeouts, 5xx, 429, and a rate-limited 403 are retried with exponential
  backoff plus jitter, then the cycle is abandoned and logged. The process stays alive; it does
  not crash-loop.
- **Shutdown.** `docker compose stop` sends `SIGTERM`; the runner finishes its in-flight cycle,
  logs `event=ingestion.shutdown`, and exits 0 within about a second.

## Development

### Modify and Reload (API)
The `api` service has volumes mounted, so Rails code changes reload automatically.

### Run Migration
```bash
docker compose exec api rails db:migrate
```

### Debug Logs
```bash
docker compose logs -f
```

## License

See [LICENSE](LICENSE).