# Architecture

## Production architecture

The repository separates user-facing bootstrapping, shared intent, and operating-system implementation.

```text
master-setup.bat
    -> pinned GitHub release ZIP
        -> config/packages.json
        -> config/profiles.json
        -> src/windows/setup.ps1
        -> future macOS/Linux adapters
```

## Bootstrap layer

`master-setup.bat` is the only required Windows download. It parses the public CLI and renders the COWEBS.LB banner. Before a real installation, it inspects the current Windows token and either continues as Administrator or performs one `RunAs` relaunch of the same canonical request; informational and dry-run paths skip this boundary. Selected packs cross the handoff as environment data rather than executable command text. The elevated bootstrap then creates a randomized temporary session, downloads the asset for its pinned version, verifies its hard-coded SHA-256, extracts it, invokes the Windows adapter, and removes only that session directory. Download, hashing, and ZIP extraction use .NET framework APIs rather than auto-loaded PowerShell modules, which keeps the handoff stable under restricted `PSModulePath` environments.

## Shared manifest layer

`packages.json` assigns stable logical keys such as `git`, `node`, and `docker`. Schema v2 also records tier, categories, license family, install strategy, dependencies, conflicts, conditions, and optional platform-specific installer overrides. Windows uses `platforms.windows.wingetId`; future adapters can add Homebrew, APT, DNF, Snap, or Flatpak fields.

`profiles.json` defines shared core packages, reusable use-case packs, role essentials, recommended packs, optional packs, and composite inheritance. The adapter resolves profile inheritance and package dependencies recursively, de-duplicates keys while preserving first-seen order, and rejects conflicts before installation.

## Platform adapter layer

The Windows PowerShell adapter owns Winget behavior, pack selection, plan validation, an elevated-real-install guard, privilege reporting, preflight estimates, colored status rendering, PATH refresh, Windows-specific configuration tracking, folders, restart handling, authorized-lab confirmation, persistent logs, and the final execution summary. The source-only Go Linux adapter owns typed Ubuntu/Fedora provider detection and direct APT, DNF, Snap, and Flatpak argument construction. It validates distribution compatibility, privilege, scope, source, and positional tokens before invoking a process and never constructs a shell command. Future adapters must consume the same logical package/profile contract while keeping operating-system behavior isolated.

Windows estimates are catalog-driven. The manifest supplies conservative fallback and disk-heavy ranges plus overrides for unusually large packages. The adapter sums the resolved dependency-free plan before Winget runs; estimates describe a fresh setup and are not a promise of exact transfer size or duration.

## Release layer

`scripts/build-release.ps1` produces the minimal runtime ZIP. Tests validate manifests and every profile directly, then simulate the complete BAT-to-ZIP-to-engine-to-cleanup flow without installing software.

## Architecture modernization implementation

The v6.2 source tree includes a development redesign foundation with versioned contracts without cutting those artifacts into the v6.2 runtime:

- `schema/package-catalog-v3.schema.json` separates logical package intent from typed platform-provider mappings.
- `schema/profile-catalog-v3.schema.json` gives packs and profiles explicit IDs while retaining logical references.
- `schema/execution-plan-v1.schema.json` defines a typed plan that cannot carry arbitrary command or shell fields.
- `schema/execution-event-v1.schema.json` defines the future console, journal, broker, and JSON-output event vocabulary.
- `schema/release-manifest-v1.schema.json` defines immutable multi-platform artifact metadata and hashes.
- `scripts/convert-catalog-v2-to-v3.ps1` compiles the production v2 manifests into deterministic shadow-planner inputs.
- `internal/catalog` strictly loads and cross-validates the generated catalogs.
- `internal/planner` resolves profile inheritance, packs, dependency order, conflicts, providers, estimates, and typed operations without invoking a package manager.
- `internal/adapter/windows` implements native Winget detection, argument construction, and execution without invoking command shells.
- `internal/adapter/linux` implements Ubuntu/Fedora validation, native dpkg/DNF/Snap/Flatpak detection, exact installed-state handling, and direct typed installation commands without invoking command shells.
- `internal/broker` regenerates the canonical plan from verified catalogs, requires elevation for real execution, directly invokes the allowlisted Windows provider, skips installs already satisfied by detection, and emits redacted `execution-event-v1` events.
- `internal/journal` handles strict schema-v1 JSONL event persistence, monotonic sequences, flushed atomic state snapshots, plan-bound recovery, and fail-closed resume validation.
- `internal/doctor` executes diagnostic checks across OS compatibility, package manager availability, workspace directories, and catalog integrity.
- `cmd/cowebs-setup` exposes the core via deterministic development CLI subcommands: `plan`, `broker`, `status`, `resume`, and `doctor` (with `--json` support).

The shadow planner has exact black-box parity with the production PowerShell planner. The Windows and Linux provider adapters, Windows privileged broker, journal, resume/status flow, and diagnostic CLI have unit and CLI integration coverage, including the principal tamper and recovery boundaries; this is not a claim of exhaustive security proof or real-install validation. Linux provider tests use an injected process runner and do not claim that package mappings or real installations have been validated. Schema v2 remains authoritative for `src/windows/setup.ps1` and the public release; neither the Go binary nor schema-v3 catalogs are included in that runtime ZIP.

## Target architecture

```text
native package / generated BAT / Unix bootstrap
    -> install or launch verified cowebs controller
        -> frontend: public CLI (cowebs install dev-setup) or optional native GUI
        -> shared Go application service
            -> inventory -> resolve -> plan -> consent
            -> user-scope executor
            -> one elevated typed broker for machine operations
                -> Winget / Brew / APT / DNF / Snap / Flatpak adapters
            -> structured events, JSONL journal, atomic resume state
```

`cowebs` is the planned stable umbrella CLI and `dev-setup` is its product identifier. The current `cmd/cowebs-setup` entry point remains the development engine until the shared application layer and public dispatch contract are implemented with compatibility coverage. CLI and GUI frontends must share typed controller services rather than invoking each other or duplicating planning and execution rules.

The accepted decisions and compatibility constraints are recorded in [docs/adr](adr/README.md). Runtime cutover remains blocked on disposable-VM parity and real-install validation.
