# Installation

## Windows requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Winget through Microsoft App Installer for real installation runs
- Internet access to GitHub Releases and the Winget source

Download `master-setup.bat` from the latest GitHub release. No repository clone and no preinstalled Git client are required.

Preview first:

```bat
master-setup.bat --profile everything --dry-run
```

Inspect packs and tailor a role:

```bat
master-setup.bat --list-packs
master-setup.bat --profile devops --pack cloud-azure --dry-run
```

Recommended packs are included by default. Use `--essentials-only` when you want just the shared core and the selected role's direct packages, then add only the packs you need. Repeat `--pack NAME` for multiple packs.

Version 6.2 asks for confirmation only when a requested package is not already installed. Press Enter to install it, type `>skip` (also `skip` or `s`) to omit it, or pass `--non-interactive` to install every needed package without per-package prompts.

Administrator mode is not required for previews. `--help`, `--version`, `--list-packs`, and `--dry-run` run without an elevation request. A real installation checks its Windows token and requests Administrator approval once before downloading or installing the payload. The elevated process then owns the complete setup, so ordinary Winget child processes inherit that access token instead of requesting elevation package by package.

The output reports `Privilege: Administrator` for a real installation or `Privilege: Standard user (preview only)` for an unelevated dry-run. A vendor installer can still display its own license, driver, account, or configuration interface; the bootstrap does not disable UAC or attempt to suppress security boundaries outside its process tree.

## Reading the preflight and summary

After resolving the profile and packs, the engine prints estimated fresh-install download and time ranges. Existing installations and cached Winget installers reduce both. Network speed, package versions, hardware, elevation prompts, restarts, and optional vendor components can increase actual duration.

Status labels are color-coded for scanning: `[INSTALLING]` cyan, `[SUCCESS]` green, `[SKIPPED]` yellow, `[FAILED]` red, and `[PLANNED]` magenta. The final summary lists counts, successfully configured components, and the persistent log path. Failed requested configuration contributes to the failure count and non-zero exit status. Dry-run summaries explicitly report that configuration and logging were not performed.

## Temporary and persistent files

- Temporary payload: `%TEMP%\COWebs.lb\setup-<random>`
- Persistent logs: `%LOCALAPPDATA%\COWebs.lb\Setup\logs`

The temporary payload is removed after success or failure unless `--keep-temp` is supplied.

## Other operating systems

macOS remains an architectural placeholder. Ubuntu and Fedora now have source-preview planning and execution through APT, DNF, Snap, and Flatpak. Ubuntu has 54 executable providers and 32 explicit unsupported results; Fedora has 42 executable providers and 44 explicit unsupported results over the same 86 logical keys. Linux plans include typed native manager installation and activation, scoped Flathub setup, verified and atomic Ubuntu repositories, one metadata refresh, user/elevated partitioning, and explicit manual authentication intent.

Build and inspect the preview locally:

```powershell
./scripts/convert-catalog-v2-to-v3.ps1 -OutputDirectory ./build/catalog
go build -o ./build/cowebs ./cmd/cowebs
./build/cowebs plan dev-setup --packages ./build/catalog/package-catalog.v3.json --profiles ./build/catalog/profile-catalog.v3.json --profile game --essentials-only --platform ubuntu --json
```

The v6.3.0-rc.1 Linux path is a public prerelease, not the stable workstation channel. Its guarded Ubuntu 24.04 and Fedora 44 disposable matrices cover partial inventory, installed-package skips, isolated-network failure and resume, active interruption and resume, initiating-user state ownership, redacted structured journals, login-shell PATH discovery, temporary-plan cleanup, and a second idempotent run. Trial real installations in a disposable environment before using the preview on a data-bearing workstation.

The public v6.3.0-rc.1 Unix bootstrap is `https://github.com/cowebsLB/cowebs-developer-setup/releases/download/v6.3.0-rc.1/cowebs-install-6.3.0-rc.1.sh`. Verify it against `SHA256SUMS` and its `.sigstore.json` bundle before execution. It installs the binary under `~/.local/bin` and catalogs under `~/.local/share/cowebs/catalog`. The CLI resolves that XDG-compatible catalog location. If `~/.local/bin` is absent from `PATH`, the bootstrap prints the exact export command; start a new login shell after adding it. Native DEB/RPM packages install the CLI under `/usr/bin` and catalogs under `/usr/share/cowebs/catalog`.

The released stable execution path remains Windows v6.2 through `master-setup.bat`. Consult the [support matrix](support-matrix.md) before using preview artifacts.
