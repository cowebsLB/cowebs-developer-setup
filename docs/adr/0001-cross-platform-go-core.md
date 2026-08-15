# ADR 0001: Cross-platform Go orchestration core

- Status: Accepted
- Date: 2026-08-07

## Implementation status

Implemented in the signed v6.3.0-rc.1 preview through `cmd/cowebs` and the shared Go application/controller packages. Schema v2 and `master-setup.bat` remain the stable Windows production path pending the separate Windows cutover gates.

## Context

The production Windows adapter currently owns profile resolution, dependency and conflict handling, interaction, package execution, configuration, logging, and restart behavior. Reimplementing that domain logic independently in PowerShell, Bash, Homebrew, APT, and DNF adapters would cause platform drift. Node.js, Python, and PowerShell 7 cannot be assumed to exist before the setup tool installs developer runtimes.

## Decision

Build the future `cowebs-setup` controller as a Go CLI distributed as per-platform binaries. Keep `master-setup.bat` as the Windows single-file user entry point and add a thin Unix bootstrap later. Bootstraps download and verify immutable release artifacts; the compiled controller owns platform-neutral inventory, planning, policy, events, and orchestration. Provider adapters own only platform-specific detection and execution.

The replacement is staged. Schema v2 and `src/windows/setup.ps1` remain the production runtime until a shadow-mode Go planner produces equivalent results for every supported profile, pack, dependency, conflict, and estimate case.

## Consequences

- Users do not need Go installed; CI builds standalone release binaries.
- Shared behavior is implemented and tested once.
- Platform adapters become smaller and contract-driven.
- Release engineering must build and sign multiple OS/architecture artifacts.
- The repository temporarily carries both the v6.1 runtime and the new core during parity migration.

## Compatibility guarantees

- Preserve the nine profile IDs and existing pack/package logical IDs.
- Preserve public Windows CLI options until a separately documented breaking release.
- Preserve pinned immutable release assets and checksum verification.
- Do not switch `master-setup.bat` to the new core before disposable-VM validation.
