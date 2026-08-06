# Changelog

All notable changes follow semantic versioning.

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
