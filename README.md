# StrongMind GitHub Ingestion

A Rails-based service that ingests `PushEvent` data from the public GitHub Events API, enriches it with actor and repository metadata, and stores everything durably in PostgreSQL.

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
  -c "SELECT COUNT(*) FROM actors;"
```

### Rails Console
```bash
docker compose exec api rails console
# Then: PushEvent.count, Actor.count, etc.
```

## How to Verify It's Working

After `docker compose up`, wait 30 seconds and then check:

1. **Logs show ingestion running:**
   ```bash
   docker compose logs ingest-worker
   ```
   Look for lines like: `Ingestion started mode=loop` and `Fetched X events from GitHub`

2. **Data is persisted:**
   ```bash
   docker compose exec -T db psql -U strongmind_ingestion -d strongmind_ingestion_dev \
     -c "SELECT github_event_id, ref FROM push_events LIMIT 5;"
   ```
   You should see rows with event IDs and refs.

3. **Tests pass:**
   ```bash
   docker compose run --rm test
   ```
   Should exit with exit code 0.

## Architecture

See [context.md](context.md) for full documentation on:
- Data model (push_events, actors, repositories, raw_events)
- Ingestion flow (polling, filtering, persistence)
- Enrichment flow (cache-first actor/repository resolution)
- Rate limiting (60 req/hr budget management)
- Idempotency (duplicate detection via unique constraints)
- Operational behavior (logging, signal handling, exit codes)

## Configuration

Environment variables (see `.env.example`):
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` — PostgreSQL connection
- `RAILS_ENV` — Rails environment (development, test, production)
- `LOG_LEVEL` — Log verbosity (default: info)
- `GITHUB_EVENTS_URL` — GitHub events endpoint (default: https://api.github.com/events)
- `POLL_INTERVAL_SECONDS` — Seconds between polls in loop mode (default: 60)
- `RATE_LIMIT_RESERVE` — Minimum requests to preserve (default: 10)
- `REQUEST_TIMEOUT_SECONDS` — HTTP timeout (default: 10)
- `MAX_RETRIES` — Retry attempts on transient failure (default: 3)

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