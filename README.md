# COWebs.lb Developer Setup

A branded, profile-driven developer workstation bootstrapper designed to support Windows, macOS, Ubuntu, Fedora, and future platforms from shared package and profile definitions.

Windows is the first implemented platform. Users download one file: `master-setup.bat`.

- [GitHub repository](https://github.com/cowebsLB/cowebs-developer-setup)
- [Latest release](https://github.com/cowebsLB/cowebs-developer-setup/releases/latest)
- [Download master-setup.bat v5.0.0](https://github.com/cowebsLB/cowebs-developer-setup/releases/download/v5.0.0/master-setup.bat)

## Windows quick start

Download `master-setup.bat` from the official GitHub release, then preview the complete setup:

```bat
master-setup.bat --profile everything --dry-run
```

Run the interactive branded setup:

```bat
master-setup.bat
```

The BAT downloads the pinned v5.0.0 release payload into a randomized directory under `%TEMP%\COWebs.lb`, verifies its hard-coded SHA-256 checksum, runs the Windows engine, saves logs outside the payload, and removes the temporary directory.

## Profiles

`backend`, `frontend`, `android`, `devops`, `ai`, `cyber`, `game`, `fullstack`, and `everything`.

Profiles resolve duplicate logical packages only once. The Everything profile currently resolves to 26 unique Windows packages.

## Cross-platform design

- `config/packages.json` owns logical package keys and platform-specific package-manager mappings.
- `config/profiles.json` owns reusable developer profiles and inheritance.
- `src/windows/setup.ps1` implements the Winget adapter and Windows configuration.
- `src/macos/` is reserved for the Homebrew adapter.
- `src/linux/` is reserved for Ubuntu and Fedora adapters.

Profiles remain stable as operating-system support grows. A logical `git` package can map to Winget on Windows, Homebrew on macOS, APT on Ubuntu, and DNF on Fedora.

## Safety

- Tagged release asset instead of mutable `main` content.
- SHA-256 verification before extraction or execution.
- Exact Winget package IDs.
- Temporary files scoped beneath a dedicated randomized directory.
- Cleanup targets only the directory created by the current bootstrap session.
- Authentication credentials and command output are not written to setup logs.
- `--dry-run` performs no installation, configuration, workspace, log, or restart changes.

See the [documentation index](docs/index.md), [architecture](docs/architecture.md), and [security model](docs/Security.md).
