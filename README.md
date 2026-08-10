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
- [Download the latest stable master-setup.bat](https://github.com/cowebsLB/cowebs-developer-setup/releases/latest/download/master-setup.bat)

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

Run `master-setup.bat` without arguments for the interactive branded setup. A real installation requests Administrator approval once at the beginning, then the elevated session downloads its pinned release payload into a randomized directory under `%TEMP%\COWebs.lb`, verifies its hard-coded SHA-256 checksum, runs the Windows engine, saves logs outside the payload, and removes the temporary directory. Help, version, pack listing, and dry-run commands do not request elevation.

Before installation starts, v6.2 prints a fresh-setup download range and install-time range for the resolved plan. During execution, color-coded status labels make installing, successful, skipped, and failed packages easy to scan. The final summary reports installed, skipped, failed, and configured items plus the persistent log path.

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
- `src/macos/` remains reserved for a future adapter; `internal/adapter/linux` provides the source-only typed execution foundation for Ubuntu and Fedora. Ubuntu now classifies 40 tools across the core, language/runtime/container, and database/client/browser/networking/Android slices: 25 executable providers and 15 explicit unsupported results. Five signed APT repositories use typed, digest-pinned prerequisites.

The source tree includes a dependency-free Go CLI (`cowebs-setup`) behind provider-aware schema-v3 contracts, a deterministic v2-to-v3 compatibility compiler, native Windows and Linux provider adapters, one-shot Windows privileged broker, structured JSONL journal with atomic state snapshots, and system diagnostic engine (`doctor`). Its independent parity harness matches the production PowerShell planner's exact Windows package order, selected packs, conflicts, and estimates for every profile in default and essentials-only modes. The compiler emits reviewed Ubuntu providers and typed repository prerequisites from schema v2, and the planner reports every selected package without a compatible target provider in one deterministic error. Tests cover the complete 11-package Ubuntu x64 core, a five-provider runtime slice, and a nine-provider productivity/tooling slice with PostgreSQL 18, Bruno, Postman, Redis Insight, Chrome, Firefox, Cloudflare Tunnel, ngrok, and scrcpy; selected unsupported packages produce complete deterministic diagnostics. Real Linux prerequisite mutation, orchestration, configuration handlers, downloaded-artifact execution, and bootstrapping are not yet runnable. Schema v2 and the released Windows engine remain authoritative until the separately gated runtime cutover; the Go/schema-v3 artifacts are not bundled in the v6.2 runtime ZIP. See the [architecture](docs/architecture.md) and [ADRs](docs/adr/README.md).

For unattended v6.2 runs, pass `--non-interactive` to suppress per-package confirmation. Interactive runs check whether a package is already installed before asking for confirmation, and accept `>skip`, `skip`, or `s` to omit a needed package.

## Safety

- Tagged release asset instead of mutable `main` content.
- SHA-256 verification before extraction or execution.
- Bootstrap download, hashing, and extraction do not depend on PowerShell module auto-loading.
- Exact Winget package IDs, all live-checked for v6.2.0 on 2026-08-09.
- Pre-install dependency and conflict resolution.
- One initial UAC request for a complete real installation, with visible privilege reporting and no UAC-policy bypass.
- Explicit authorized-lab confirmation for Kali WSL.
- Temporary files scoped beneath a dedicated randomized directory.
- Authentication credentials and command output are not written to setup logs.
- `--dry-run` performs no installation, configuration, workspace, log, or restart changes.

See the [documentation index](docs/index.md), [architecture](docs/architecture.md), and [security model](docs/Security.md).
