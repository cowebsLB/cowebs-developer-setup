# ADR 0002: Least-privilege coordinator and broker

- Status: Accepted
- Date: 2026-08-07

## Implementation status

Implemented for the v6.3.0-rc.1 Linux preview as one direct-argument `sudo` handoff with user-scoped work retained by the initiating process, streamed validated events, process-group interruption, and bounded cleanup. The Go Windows controller-owned `RunAs` handoff remains a cutover gate; stable v6.2 keeps its existing single bootstrap elevation.

## Context

The v6.1 BAT requests elevation before payload download, verification, extraction, planning, installation, and user configuration. This consolidates UAC prompts but expands the privileged network, archive, and configuration surface. Future platforms also distinguish user-scoped managers such as Homebrew from machine-scoped managers such as APT and DNF.

## Decision

The future controller remains unelevated while it downloads and verifies artifacts, inventories the machine, resolves the selected profile, constructs the execution plan, and obtains consent. It then requests elevation once for a narrow broker that performs only typed, allowlisted machine operations.

The broker receives logical package IDs, provider IDs, catalog digest, and plan/session identifiers. It reloads the verified catalog and constructs argument arrays itself. It must reject arbitrary command text, shell fields, unknown provider options, mismatched catalog digests, and user-configuration operations. The original controller waits for broker events and resumes unelevated configuration afterward.

## Consequences

- One elevation request remains the intended user experience.
- Network download, archive handling, planning, and user configuration leave the privileged boundary.
- Provider mappings must declare privilege and installation scope explicitly.
- Windows named-pipe and Unix local-socket authentication require dedicated threat modeling and tests.
- The current v6.1 elevation flow remains unchanged until the broker is implemented and validated.

## Security invariants

- Never disable UAC, cache administrator credentials, or run the full controller as `SYSTEM`.
- Never execute broker input through a command shell.
- Never accept installer flags that are absent from the verified catalog.
- Redact authentication and credential material before emitting structured events.
