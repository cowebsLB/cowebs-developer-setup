# Architecture

## Production architecture

The repository separates user-facing bootstrapping, shared intent, and operating-system implementation.

```text
master-setup.bat
    -> pinned GitHub release ZIP
        -> config/packages.json
        -> config/profiles.json
        -> src/windows/setup.ps1
        -> released Windows adapter
        -> source-preview Linux controller and adapters
        -> future macOS adapter
```

## Bootstrap layer

`master-setup.bat` is the only required Windows download. It parses the public CLI and renders the COWEBS.LB banner. Before a real installation, it inspects the current Windows token and either continues as Administrator or performs one `RunAs` relaunch of the same canonical request; informational and dry-run paths skip this boundary. Selected packs cross the handoff as environment data rather than executable command text. The elevated bootstrap then creates a randomized temporary session, downloads the asset for its pinned version, verifies its hard-coded SHA-256, extracts it, invokes the Windows adapter, and removes only that session directory. Download, hashing, and ZIP extraction use .NET framework APIs rather than auto-loaded PowerShell modules, which keeps the handoff stable under restricted `PSModulePath` environments.

## Shared manifest layer

`packages.json` assigns stable logical keys such as `git`, `node`, and `docker`. Schema v2 also records tier, categories, license family, install strategy, dependencies, conflicts, conditions, and Windows/Ubuntu compatibility mappings. `config/fedora-packages.json` adds one reviewed classification for every existing logical key without duplicating profiles. Supported Linux entries use a typed manager, package ID, privilege, scope, architectures, installer options, and conservative estimate policy. `ubuntuPrerequisites` defines reusable signed APT repositories as typed HTTPS URLs, a pinned keyring digest and constrained target, repository suite/components, architectures, and a constrained sources-list target; no catalog accepts command or shell fields.

`profiles.json` defines shared core packages, reusable use-case packs, role essentials, recommended packs, optional packs, and composite inheritance. The adapter resolves profile inheritance and package dependencies recursively, de-duplicates keys while preserving first-seen order, and rejects conflicts before installation.

## Platform adapter layer

The Windows PowerShell adapter owns the released Winget runtime. The source-preview Go Linux adapter owns Ubuntu/Fedora detection and direct APT, DNF, Snap, and Flatpak execution. It also performs bounded HTTPS key retrieval, digest verification, constrained atomic repository writes, one metadata refresh, typed native manager installation/activation, scoped remote setup, and Linux configuration handlers. `internal/application` is the shared frontend boundary. It partitions the canonical plan so machine operations cross one explicit `sudo` handoff while user Flatpak and configuration operations remain in the initiating user's process. The parent validates and persists elevated events as a stream, so completed work remains resumable even when a later operation fails. Future adapters must consume the same logical package/profile contract while keeping operating-system behavior isolated.

Windows estimates are catalog-driven. The manifest supplies conservative fallback and disk-heavy ranges plus overrides for unusually large packages. The adapter sums the resolved dependency-free plan before Winget runs; estimates describe a fresh setup and are not a promise of exact transfer size or duration.

## Release layer

`scripts/build-release.ps1` continues to produce the released Windows v6.2 runtime ZIP. `scripts/build-cross-platform.ps1` separately builds the source-preview `cowebs` binaries, deterministic catalogs, checksum-pinned Unix bootstrap, release manifest, SHA-256 list, SPDX SBOM, and Winget metadata. Debian and RPM definitions are built independently on Linux by `scripts/build-linux-packages.sh`; disposable Ubuntu 24.04 and Fedora 44 package-manager verification has passed for the unsigned preview formats. Preview packaging does not change the production BAT payload.

## Architecture modernization implementation

The v6.2 source tree includes a development redesign foundation with versioned contracts without cutting those artifacts into the v6.2 runtime:

- `schema/package-catalog-v3.schema.json` separates logical package intent from typed platform-provider mappings and reusable signed-repository prerequisites.
- `schema/profile-catalog-v3.schema.json` gives packs and profiles explicit IDs while retaining logical references.
- `schema/execution-plan-v1.schema.json` defines a typed plan that cannot carry arbitrary command or shell fields.
- `schema/execution-event-v1.schema.json` defines the future console, journal, broker, and JSON-output event vocabulary.
- `schema/release-manifest-v1.schema.json` defines immutable multi-platform artifact metadata and hashes.
- `scripts/convert-catalog-v2-to-v3.ps1` compiles the production v2 manifests and reviewed Fedora compatibility input into deterministic planner catalogs without hand-maintaining schema-v3 output.
- `internal/catalog` strictly loads and cross-validates the generated catalogs.
- `internal/planner` resolves profile inheritance, packs, dependency order, conflicts, providers, prerequisites, estimates, and typed operations without invoking a package manager; missing target providers are returned together in deterministic logical-package order. Shared APT repository setup is emitted once, followed by one package-index refresh on which dependent installs wait.
- `internal/adapter/windows` implements native Winget detection, argument construction, and execution without invoking command shells.
- `internal/adapter/linux` implements Ubuntu/Fedora validation, dpkg/DNF/Snap/Flatpak detection, direct typed installation, verified atomic APT prerequisites, and typed Flatpak remote setup without command shells.
- `internal/configuration` maps supported Linux configuration intents to allowlisted argument arrays and reports authentication/account intents as manual without persisting credentials.
- `internal/application` exposes shared catalog, planning, partitioned execution, and state services to the CLI and future GUI.
- `internal/broker` regenerates canonical plans, enforces platform and privilege partitions, skips satisfied operations, and emits redacted `execution-event-v1` events.
- `internal/journal` handles strict schema-v1 JSONL event persistence, monotonic sequences, flushed atomic state snapshots, plan-bound recovery, and fail-closed resume validation.
- `internal/doctor` executes diagnostic checks across OS compatibility, package manager availability, workspace directories, and catalog integrity.
- `cmd/cowebs` exposes the public preview command family under the stable `dev-setup` product identifier; `cmd/cowebs-setup` remains the development compatibility entry point.

The planner retains exact black-box parity with the production PowerShell planner. Tests compile all 86 Ubuntu and Fedora classifications, prove deterministic core and bounded plans, validate typed APT/DNF/Snap/Flatpak prerequisites, exercise verified atomic repository writes with injected downloads, test privilege partitioning and configuration handling, and verify the public CLI and cross-platform release outputs. Real installation evidence is still pending in disposable Ubuntu and Fedora environments, so schema v2 remains authoritative for the public Windows v6.2 runtime.

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
