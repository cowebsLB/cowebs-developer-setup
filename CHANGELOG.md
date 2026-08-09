# Changelog

All notable changes follow semantic versioning.

## [Unreleased]

### Changed

- Promoted GitHub CLI from explicit Ubuntu unsupported status to a conditional official APT provider backed by a typed, SHA-256-pinned signed-repository prerequisite.
- Extended package catalog v3 and execution plan v1 with typed repository-key, APT source, and de-duplicated package-index refresh contracts while keeping real Linux prerequisite mutation disabled.
- Extended the deterministic schema-v2 compatibility input and compiler with reviewed Ubuntu support classifications, typed APT/Snap provider mappings, architecture ranges, options, privilege/scope, and conservative estimates for the bounded core slice.
- Changed planner failure behavior to report every selected package lacking a target provider in deterministic plan order.
- Advanced development builds to `6.3.0-dev` and protected the published v6.2.0 identity from rebuilds on newer source.
- Expanded the Linux roadmap into staged Ubuntu, Fedora, privilege-orchestration, immutable-bootstrap, disposable-environment validation, and release-readiness gates.
- Added the planned public `cowebs install dev-setup` command family, shared CLI/GUI controller boundary, native packaging targets, compatibility requirements, and end-to-end product-surface gates to the roadmap and API documentation.

### Added

- Added a deterministic full 11-package Ubuntu x64 core plan and safe Linux prerequisite dry-run rendering for the official GitHub CLI repository.
- Added reviewed Ubuntu core classifications, an explicit GNOME Terminal alternative, and conditional Snap mappings for VS Code and PowerShell.
- Added bounded Ubuntu compilation/planning and planner-to-adapter detection/dry-run tests with byte-deterministic JSON assertions.
- Added a source-only typed Linux provider adapter for Ubuntu and Fedora with direct `apt-get`, `dnf`, `snap`, and `flatpak` detection and installation commands.
- Added Linux adapter tests for manager/platform compatibility, user and machine Flatpak scopes, dry-run isolation, process-start failures, native inventory queries, and unsafe positional-token rejection.

### Security

- Pinned the GitHub CLI keyring by its official SHA-256, constrained repository URLs to credential-free HTTPS, constrained target files to APT-owned directories, and rejected real prerequisite execution until an elevated atomic implementation is reviewed.
- Rejected unknown fields, stringly typed installer options, invalid provider contracts, and arbitrary shell data in Ubuntu compatibility mappings; unsupported packages never compile into executable providers.
- Required explicit Linux privilege, scope, and Flatpak remote contracts; rejected unsupported cross-distribution managers, custom APT/DNF/Snap sources, option-shaped identifiers/remotes, and malformed or control-character arguments before process execution.
- Made APT detection require the exact installed dpkg status instead of treating residual configuration state as an installed package.

## [6.2.0] - 2026-08-09

### Added

- Added structured execution journal and state snapshot module (`internal/journal`) for tracking execution events and enabling atomic state recovery.
- Added system diagnostic engine (`internal/doctor`) for platform compatibility, package manager availability, workspace directory verification, and catalog integrity checks.
- Added `cowebs-setup status`, `cowebs-setup resume`, and `cowebs-setup doctor` CLI subcommands with `--json` output format support.
- Added Windows provider adapter (`internal/adapter/windows`) for native `winget` detection, argument construction, and execution.
- Added one-shot privileged broker (`internal/broker`) enforcing catalog digest verification, privilege scope isolation, option allowlisting, and structured `execution-event-v1` JSON stream emissions.
- Added `cowebs-setup broker` CLI command to execute validated execution plans via the privileged broker engine.
- Added comprehensive package descriptions to all 86 package definitions in the catalog detailing function, operation, and use case.
- Added interactive package skipping with `>skip` prompt after installed-package detection, backed by `-NonInteractive` and the bootstrap `--non-interactive` option for automated runs.
- Added JSON Schema draft 2020-12 contracts for provider-aware package catalog v3, profile catalog v3, typed execution plans, structured execution events, and multi-platform release manifests.
- Added a deterministic Windows PowerShell 5-compatible schema-v2 to schema-v3 compiler that preserves the complete production catalog and profile contract.
- Added accepted architecture decisions for a staged Go core, least-privilege broker, provider-aware adapters, and resumable structured execution state.
- Added a dependency-free Go 1.26.5 catalog loader, deterministic shadow planner, and JSON CLI that emit typed detection, installation, and configuration operations without changing the production runtime.

### Security

- Made the broker regenerate and require the exact canonical plan from verified catalogs before any operation, reject unknown plan fields, require an elevated Windows token for real execution, and keep raw installer output out of structured journals.
- Made resume fail closed on corrupt, structurally incomplete, or plan/catalog-mismatched state, and made journal event parsing enforce the schema-v1 vocabulary and monotonic sequence contract.
- Prohibited arbitrary command and shell fields from future execution plans and required explicit provider privilege, scope, native detection, and typed installer options.
- Made ambiguous quoted legacy overrides fail migration instead of applying lossy tokenization.
- Made the Go loader reject unknown JSON fields, trailing values, invalid references, asymmetric conflicts, unsupported targets, and incomplete provider mappings before planning.

### Fixed

- Fixed the release builder defaulting to an already-published identity; development builds used `6.2.0-dev`, and the release tag now reproduces `6.2.0` while rejecting older published immutable versions.
- Fixed the broker installing packages even after native detection reported them as already installed.
- Fixed process-launch failures being misclassified as successful installed-package detection.
- Fixed resume suppressing new journal events, changing session identity, ignoring state-load failures, and accepting state from another plan or catalog.
- Fixed journal sequence reuse after reopening a session and made snapshot writes flush temporary state before atomic replacement.
- Fixed per-package prompts appearing before the engine checked whether a package was already installed.
- Fixed diagnostic status vocabulary and partial catalog-path handling.

### Testing

- Added deterministic compilation, complete semantic parity, schema-contract, unknown-reference, and unsafe-override regression coverage without cutting the Go/schema-v3 architecture into the production runtime.
- Added Go unit tests and independent black-box parity coverage for all nine profiles in default and essentials-only modes, explicit multi-pack composition, conflict rejection, exact estimates, operation counts, and byte-identical output.
- Added canonical-plan tamper rejection, process-start failure, installed-package skip, durable resume, sequence continuity, mismatched-state, unknown-field, and non-interactive bootstrap regression coverage.
- Updated Windows CI to Node 24-compatible `actions/checkout@v7` and `actions/setup-go@v7`, pinned through `go.mod`.

## [6.1.0] - 2026-08-07

### Added

- Added plan-level estimated download-size and install-time ranges before package processing begins.
- Added catalog-owned Windows estimation policy with conservative defaults and heavyweight-package overrides.
- Added a structured final summary listing installed, skipped, failed, and configured items plus the persistent log path.
- Added one-time bootstrap self-elevation and visible privilege reporting for real Windows installations.

### Changed

- Standardized colored status labels: green success, yellow skipped, red failed, cyan installing, and magenta planned.
- Configuration actions now record only components whose requested configuration completed successfully.
- Failed configuration actions now contribute to the final failure count and non-zero setup exit status.
- Changed the README download link to the stable GitHub `latest` asset URL so it remains valid between source and release publication.
- Help, version, pack-listing, and dry-run paths remain unelevated, while the Windows engine rejects direct unelevated real-install execution.

### Security

- Preserved selected pack names across the elevated handoff through a validated environment-data channel rather than command-line interpolation.
- Kept Windows UAC enabled and avoided credential storage, `SYSTEM` execution, or global consent-policy changes.

### Testing

- Added validation for estimate ranges and override references, status color contracts, estimate output, configuration summary output, privilege rendering, one-time elevation contracts, dry-run elevation bypass, and end-to-end bootstrap rendering.

## [6.0.0] - 2026-08-07

### Added

- Expanded the Windows catalog from 26 to 86 live-verified exact Winget packages.
- Added 34 reusable use-case packs covering language stacks, databases, frontend handoff, tunnels, WSL, Kubernetes, IaC, cloud providers, AI/ML, authorized security testing, and game production.
- Added repeatable `--pack NAME`, `--essentials-only`, and `--list-packs` bootstrap options.
- Added package tiers, categories, license metadata, dependencies, conflicts, install conditions, and package-specific Winget overrides.
- Added README status, release, license, platform, and manifest-schema badges.

### Changed

- Upgraded both shared manifests to schema v2 and separated shared core tools, role essentials, recommendations, and optional use cases.
- Made role defaults professional but bounded; heavy engines, cloud CLIs, alternate runtimes, and specialized labs remain opt-in.
- Renamed the broad profile to `Everything Essentials` and limited its default plan to the recommended cross-role toolset.
- Updated the Windows engine to resolve dependencies recursively, deduplicate packages, merge inherited packs, and describe relevant hardware, disk, and restart conditions.

### Security

- Added fail-fast conflict detection for incompatible Python environment strategies.
- Added explicit confirmation before a real authorized Kali WSL lab installation.
- Kept explicit pack names in an environment handoff rather than interpolating them into the PowerShell command line.

### Fixed

- Replaced bootstrap dependencies on `Invoke-WebRequest`, `Get-FileHash`, and `Expand-Archive` with .NET download, SHA-256, and ZIP APIs so GitHub Actions and other restricted `PSModulePath` environments can complete the verified handoff.

### Testing

- Added manifest metadata and reference integrity tests, every-profile default and essentials-only dry-runs, compatible pack composition, expected conflict coverage, pack listing, and an end-to-end repeated-pack bootstrap simulation.
- Added end-to-end coverage with an intentionally restricted PowerShell module path to prevent recurrence of the CI bootstrap failure.
- Verified all 86 exact package IDs against the live Winget source.

## [5.0.0] - 2026-08-07

### Added

- Single-file Windows bootstrap backed by a pinned, checksum-verified GitHub release asset.
- Shared JSON package catalog with 26 logical packages and Windows Winget mappings.
- Shared JSON profile catalog with inheritance and duplicate elimination.
- Windows PowerShell setup engine with installation, optional configuration, persistent logging, workspace creation, dry-run mode, and exit-code reporting.
- Release bundle builder, full bootstrap simulation, GitHub Actions validation, MIT license, and future macOS/Linux adapter boundaries.

### Changed

- Converted `master-setup.bat` from a monolithic installer into the branded verified bootstrap.
- Everything now processes each logical package once instead of repeating package checks across component profiles.
- Setup logs now live under `%LOCALAPPDATA%\COWebs.lb\Setup\logs` so temporary cleanup cannot remove them.

### Security

- Pinned the v5.0.0 payload SHA-256 in the bootstrap.
- Added randomized, narrowly scoped temporary extraction and automatic cleanup.
- Avoided a Git dependency and mutable branch execution by using a release ZIP.

## [4.0.2] - 2026-08-07

### Fixed

- Extended the block-letter banner from `COWEBS` to the complete `COWEBS.LB` brand name.
- Widened and re-centered the branded header around the complete artwork.
- Added a regression assertion for the `.LB` portion of the banner.

## [4.0.1] - 2026-08-06

### Changed

- Replaced the compact text heading with the full COWEBS block-letter banner from the branded prototype.
- Enabled UTF-8 console output so the banner renders correctly in Unicode-capable Windows terminals.
- Restored the caller's original console code page on every top-level exit path.
- Added automated assertions for the banner and UTF-8 console initialization.

## [4.0.0] - 2026-08-06

### Added

- Branded COWebs.lb master setup with nine developer profiles.
- Complete package coverage from all three prototype scripts.
- Safe `--dry-run`, `--profile`, `--no-config`, `--no-restart`, and `--help` options.
- Append-only session logging, installation counters, failure exit codes, PATH refresh, and optional tool configuration.
- Automated static, control-flow, and dry-run tests.
- Project documentation and dated engineering worklog.

### Changed

- Replaced stale Winget IDs with current exact IDs.
- Made elevation optional and delegated package-specific elevation to Winget.
- Moved configuration after package installation and PATH refresh.

### Fixed

- Full Stack and Everything profiles now return from each component profile and show completion only once.
- Invalid menu and CLI profile input now produces deterministic behavior.
- Branding uses portable console-safe characters instead of an incorrectly decoded UTF-8 banner.
- Installation failures are counted, logged, and returned through a non-zero process exit code.
