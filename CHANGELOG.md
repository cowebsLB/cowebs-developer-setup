# Changelog

All notable changes follow semantic versioning.

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
