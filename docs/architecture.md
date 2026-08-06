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

`master-setup.bat` is the only required Windows download. It parses the public CLI and renders the COWEBS.LB banner. Before a real installation, it inspects the current Windows token and either continues as Administrator or performs one `RunAs` relaunch of the same canonical request; informational and dry-run paths skip this boundary. Selected packs cross the handoff as environment data rather than executable command text. The elevated bootstrap then creates a randomized temporary session, downloads the asset for its pinned version, verifies its hard-coded SHA-256, extracts it, invokes the Windows adapter, and removes only that session directory. Download, hashing, and ZIP extraction use .NET framework APIs rather than auto-loaded PowerShell modules, which keeps the handoff stable under restricted `PSModulePath` environments.

## Shared manifest layer

`packages.json` assigns stable logical keys such as `git`, `node`, and `docker`. Schema v2 also records tier, categories, license family, install strategy, dependencies, conflicts, conditions, and optional platform-specific installer overrides. Windows uses `platforms.windows.wingetId`; future adapters can add Homebrew, APT, DNF, Snap, or Flatpak fields.

`profiles.json` defines shared core packages, reusable use-case packs, role essentials, recommended packs, optional packs, and composite inheritance. The adapter resolves profile inheritance and package dependencies recursively, de-duplicates keys while preserving first-seen order, and rejects conflicts before installation.

## Platform adapter layer

The Windows PowerShell adapter owns Winget behavior, pack selection, plan validation, an elevated-real-install guard, privilege reporting, preflight estimates, colored status rendering, PATH refresh, Windows-specific configuration tracking, folders, restart handling, authorized-lab confirmation, persistent logs, and the final execution summary. Future adapters must consume the same logical package/profile contract while keeping operating-system behavior isolated.

Windows estimates are catalog-driven. The manifest supplies conservative fallback and disk-heavy ranges plus overrides for unusually large packages. The adapter sums the resolved dependency-free plan before Winget runs; estimates describe a fresh setup and are not a promise of exact transfer size or duration.

## Release layer

`scripts/build-release.ps1` produces the minimal runtime ZIP. Tests validate manifests and every profile directly, then simulate the complete BAT-to-ZIP-to-engine-to-cleanup flow without installing software.
