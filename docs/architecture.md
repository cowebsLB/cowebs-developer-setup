# Architecture

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

`master-setup.bat` is the only required Windows download. It parses the public CLI, renders the COWEBS.LB banner, creates a randomized temporary session, downloads the v6.0.0 asset, verifies its hard-coded SHA-256, extracts it, invokes the Windows adapter, and removes only that session directory. Download, hashing, and ZIP extraction use .NET framework APIs rather than auto-loaded PowerShell modules, which keeps the handoff stable under restricted `PSModulePath` environments. Explicit pack names cross this boundary through `COWEBS_SETUP_PACKS`, avoiding command-line interpolation.

## Shared manifest layer

`packages.json` assigns stable logical keys such as `git`, `node`, and `docker`. Schema v2 also records tier, categories, license family, install strategy, dependencies, conflicts, conditions, and optional platform-specific installer overrides. Windows uses `platforms.windows.wingetId`; future adapters can add Homebrew, APT, DNF, Snap, or Flatpak fields.

`profiles.json` defines shared core packages, reusable use-case packs, role essentials, recommended packs, optional packs, and composite inheritance. The adapter resolves profile inheritance and package dependencies recursively, de-duplicates keys while preserving first-seen order, and rejects conflicts before installation.

## Platform adapter layer

The Windows PowerShell adapter owns Winget behavior, pack selection, plan validation, PATH refresh, Windows-specific configuration, folders, restart handling, authorized-lab confirmation, and persistent logs. Future adapters must consume the same logical package/profile contract while keeping operating-system behavior isolated.

## Release layer

`scripts/build-release.ps1` produces the minimal runtime ZIP. Tests validate manifests and every profile directly, then simulate the complete BAT-to-ZIP-to-engine-to-cleanup flow without installing software.
