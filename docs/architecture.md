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

`master-setup.bat` is the only required Windows download. It parses the public CLI, renders the COWEBS.LB banner, creates a randomized temporary session, downloads the v5.0.0 asset, verifies its hard-coded SHA-256, extracts it, invokes the Windows adapter, and removes only that session directory.

## Shared manifest layer

`packages.json` assigns stable logical keys such as `git`, `node`, and `docker`. Each package contains platform mappings. Windows uses `platforms.windows.wingetId`; future adapters can add Homebrew, APT, DNF, Snap, or Flatpak fields.

`profiles.json` groups logical keys into developer profiles. Composite profiles inherit other profiles. The adapter resolves inheritance recursively and de-duplicates keys while preserving first-seen order.

## Platform adapter layer

The Windows PowerShell adapter owns Winget behavior, PATH refresh, Windows-specific configuration, folders, restart handling, and persistent logs. Future adapters must consume the same logical package/profile contract while keeping operating-system behavior isolated.

## Release layer

`scripts/build-release.ps1` produces the minimal runtime ZIP. Tests validate manifests and every profile directly, then simulate the complete BAT-to-ZIP-to-engine-to-cleanup flow without installing software.
