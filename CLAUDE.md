# CLAUDE.md — Agent Operating Rules

## 1. Read First
- Read `context.md` before writing code.
- If a request conflicts with the architecture in `context.md`, stop and ask. Do not improvise.

## 2. Architectural Guardrails (do not violate without explicit human approval)
- Rails API-only. No view layer, no asset pipeline.
- No background jobs, queues, Redis, Sidekiq, or cron daemons.
- PostgreSQL is the only system of record.
- Ingestion runs through `bin/ingest` and nothing else.
- No authenticated GitHub requests. No token, ever.
- No new top-level dependency without justification in the PR description.

## 3. Coding Standards
- Ruby style: [Ruby Style Guide](https://rubystyle.guide/), enforced by RuboCop; the config is authoritative.
- Service objects live in `app/services`, namespaced, one public entry point each.
- Models hold persistence concerns only: no HTTP, no logging, no orchestration.
- Configuration is read from `Ingestion.config`, never from `ENV` at a call site.
- Every log line goes to stdout/stderr and carries the `run_id`.
- Fail loudly on programmer error; fail gracefully on upstream and network error.

## 4. SOLID in This Codebase
- **S:** `Github::Client` speaks HTTP; `EventFilter` selects; `EventProcessor` persists; `Enricher` enriches; `Runner` orchestrates. If a class needs "and" to describe it, split it.
- **O:** New event types are handled by adding a filter/processor, not by editing existing ones.
- **L:** Test doubles must honour the real collaborator's contract, including its error classes.
- **I:** Collaborators expose narrow interfaces; the runner depends on behaviour, not internals.
- **D:** Collaborators are constructor-injected so tests need no global stubbing.

## 5. Testing Expectations
- Every service object has unit tests. Every story has at least one integration test.
- No live network calls: WebMock blocks outbound HTTP by default.
- Idempotency, malformed input, and rate-limit exhaustion are tested explicitly — they are the behaviours this project is judged on.
- Tests must pass offline via `docker compose run --rm test`.

## 6. Coverage
- SimpleCov enabled; minimum 85% overall, 95% on `app/services`.
- Do not add assertion-free tests to move the number.

## 7. Do
- Keep migrations reversible; commit `db/schema.rb` with them.
- Update `context.md` in the same commit as any change to architecture, data model, or flows.
- Update `CHANGELOG.md` after merging a story branch to `main`.
- Keep README verification steps true after every change.
- Write one-line comments only, and only for the WHY when non-obvious.

## 8. Don't
- Don't add features not in the plan of record.
- Don't reach for a new gem where the standard library suffices.
- Don't swallow exceptions silently — log with context or re-raise.
- Don't edit migrations that are already merged.
- Don't let documentation drift from code across a commit boundary.
- Don't write docstrings or multi-line comment blocks.
- Don't add error handling for scenarios that cannot happen (trust internal code).

## 9. When Documentation Must Change
Any change to the data model, ingestion flow, enrichment flow, rate-limit strategy, idempotency strategy, or operational behaviour requires a `context.md` update in the same commit. A PR that changes behaviour without touching `context.md` is incomplete.
