# ADR 0003: Provider-aware catalog schema v3

- Status: Accepted
- Date: 2026-08-07

## Implementation status

Implemented as deterministic schema-v3 preview catalogs compiled from schema v2 plus reviewed platform compatibility input. The v6.3.0-rc.1 artifacts contain those generated catalogs; schema v2 remains the production source of truth and generated v3 output is not hand-maintained.

## Context

Schema v2 provides stable logical keys, profiles, packs, dependencies, conflicts, and Windows Winget mappings. It also places `installStrategy: winget` on every package, stores Windows estimates at catalog root, and permits a raw `wingetOverride` string. Adding more manager IDs to the same shape would mix logical intent with platform execution and leave privilege, scope, detection, architecture, and unsupported-platform behavior implicit.

## Decision

Schema v3 separates package intent from provider mappings. Logical packages own metadata, dependencies, conflicts, conditions, and configuration intents. Platform provider entries own manager, exact package ID, source, privilege, scope, architecture, native detection, typed installer-option tokens, and estimates.

Profiles and packs continue to reference logical IDs only. Execution plans reference logical packages and typed provider selections; they contain no arbitrary command or shell field.

The repository keeps schema v2 as the production source during migration. `scripts/convert-catalog-v2-to-v3.ps1` compiles deterministic v3 catalogs for shadow-planner development and fails when v2 data cannot be represented safely. It does not edit v2 files or alter the release bundle.

## Consequences

- Platform adapters can share one logical catalog without sharing manager syntax.
- Privilege and user/machine scope become reviewable data.
- Raw quoted legacy overrides require explicit manual migration instead of lossy tokenization.
- Catalog source may later be split by category, provided release builds compile one canonical validated catalog.
- Schema evolution requires converters and compatibility tests rather than in-place reinterpretation.
