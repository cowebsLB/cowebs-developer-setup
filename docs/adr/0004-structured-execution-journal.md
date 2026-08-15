# ADR 0004: Structured plans, events, and execution journal

- Status: Accepted
- Date: 2026-08-07

## Implementation status

Implemented in the v6.3.0-rc.1 preview as a strictly decoded, redacted JSONL journal plus flushed atomic state snapshot. Guarded Ubuntu and Fedora interruption/resume matrices passed; no application database was introduced.

## Context

The current engine writes human-readable text logs and final counters. It cannot durably distinguish unattempted, successful, skipped, retryable, blocked, cancelled, configuration-failed, or restart-pending operations after interruption. A future CLI, broker, resume command, and optional GUI need one machine-readable execution model.

## Decision

Define versioned JSON contracts for execution plans and events. The future controller will append redacted events to a JSONL journal and periodically replace an atomic state snapshot. Resume is permitted only when plan and catalog digests match or an explicit replan migration is accepted.

Do not introduce an application database for the first implementation. The expected state volume is small, append-only events are inspectable and recoverable, and an atomic file model avoids migration and locking complexity during bootstrap.

## Consequences

- Human console output and JSON output consume the same event stream.
- Exit classification, retries, summaries, and resume behavior become testable without real installers.
- Event schemas must evolve compatibly and logs must remain secret-free.
- A database may be reconsidered only if concurrent sessions, queries, or state volume outgrow the file journal.
