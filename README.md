# COWebs.lb Developer Setup

[![Validate setup](https://github.com/cowebsLB/cowebs-developer-setup/actions/workflows/validate.yml/badge.svg)](https://github.com/cowebsLB/cowebs-developer-setup/actions/workflows/validate.yml)
[![Latest release](https://img.shields.io/github/v/release/cowebsLB/cowebs-developer-setup?label=release)](https://github.com/cowebsLB/cowebs-developer-setup/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows11&logoColor=white)](docs/installation.md)
[![Manifest schema](https://img.shields.io/badge/manifest-v2-0B7285)](docs/API.md)

A branded, profile-driven developer workstation bootstrapper designed to support Windows, macOS, Ubuntu, Fedora, and future platforms from shared package and profile definitions.

Windows is the first implemented platform. Users download one file: `master-setup.bat`.

- [GitHub repository](https://github.com/cowebsLB/cowebs-developer-setup)
- [Latest release](https://github.com/cowebsLB/cowebs-developer-setup/releases/latest)
- [Download master-setup.bat v6.0.0](https://github.com/cowebsLB/cowebs-developer-setup/releases/download/v6.0.0/master-setup.bat)

## Windows quick start

Preview a role and its recommended packs:

```bat
master-setup.bat --profile backend --dry-run
```

Add one or more focused use-case packs:

```bat
master-setup.bat --profile backend --pack backend-python --pack cloud-aws --dry-run
```

List every available pack or install only the shared core and role essentials:

```bat
master-setup.bat --list-packs
master-setup.bat --profile ai --essentials-only --pack ai-conda --dry-run
```

Run `master-setup.bat` without arguments for the interactive branded setup. The BAT downloads the pinned v6.0.0 release payload into a randomized directory under `%TEMP%\COWebs.lb`, verifies its hard-coded SHA-256 checksum, runs the Windows engine, saves logs outside the payload, and removes the temporary directory.

## Profiles and packs

The nine profiles are `backend`, `frontend`, `android`, `devops`, `ai`, `cyber`, `game`, `fullstack`, and `everything`. Each profile combines:

- 11 shared core utilities;
- lean role essentials;
- recommended use-case packs by default;
- optional packs selected interactively or with repeatable `--pack NAME` arguments.

The schema-v2 catalog contains 86 exact Windows package mappings and 34 packs for languages, databases, browsers, API work, cloud providers, WSL, Kubernetes, infrastructure as code, supply-chain security, AI/ML, authorized security labs, and game production. Dependencies are added automatically, duplicate packages are removed, and incompatible environment choices fail before installation.

See the [package and profile guide](docs/package-selection.md) for the complete role-to-pack map and the evidence behind the defaults.

## Cross-platform design

- `config/packages.json` owns logical package keys, metadata, dependencies, conflicts, conditions, and platform mappings.
- `config/profiles.json` owns shared core tools, role essentials, reusable packs, recommendations, optional choices, and inheritance.
- `src/windows/setup.ps1` implements the Winget adapter and Windows configuration.
- `src/macos/` and `src/linux/` are reserved for future adapters that consume the same logical keys.

## Safety

- Tagged release asset instead of mutable `main` content.
- SHA-256 verification before extraction or execution.
- Bootstrap download, hashing, and extraction do not depend on PowerShell module auto-loading.
- Exact Winget package IDs, all live-checked for v6.0.0.
- Pre-install dependency and conflict resolution.
- Explicit authorized-lab confirmation for Kali WSL.
- Temporary files scoped beneath a dedicated randomized directory.
- Authentication credentials and command output are not written to setup logs.
- `--dry-run` performs no installation, configuration, workspace, log, or restart changes.

See the [documentation index](docs/index.md), [architecture](docs/architecture.md), and [security model](docs/Security.md).
