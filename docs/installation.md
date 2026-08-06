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

macOS, Ubuntu, and Fedora adapters are architectural placeholders in v6.1.0 and are not yet runnable. The schema-v2 intent is cross-platform, but the current package mappings and tested execution path are Windows-only.
