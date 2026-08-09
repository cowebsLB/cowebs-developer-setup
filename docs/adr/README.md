# Architecture Decision Records

Architecture Decision Records capture durable technical decisions for the cross-platform redesign. Accepted ADRs are binding until superseded by a later record. They do not change the production runtime unless an implementation milestone explicitly says so.

| ADR | Status | Decision |
|---|---|---|
| [0001](0001-cross-platform-go-core.md) | Accepted | Build the future orchestration core as a compiled Go CLI through staged replacement. |
| [0002](0002-least-privilege-broker.md) | Accepted | Keep coordination unelevated and use one narrow privileged broker for machine operations. |
| [0003](0003-provider-aware-schema-v3.md) | Accepted | Separate logical intent from typed platform-provider mappings in schema v3. |
| [0004](0004-structured-execution-journal.md) | Accepted | Use structured plans, events, and a resumable JSONL journal before considering a database. |
