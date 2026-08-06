# Installation

## Windows requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Winget through Microsoft App Installer for real installation runs
- Internet access to GitHub Releases and the Winget source

Download `master-setup.bat` from the v6.0.0 GitHub release. No repository clone and no preinstalled Git client are required.

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

Administrator mode is not required for the bootstrap. Winget or individual installers can request elevation when their manifests require it.

## Temporary and persistent files

- Temporary payload: `%TEMP%\COWebs.lb\setup-<random>`
- Persistent logs: `%LOCALAPPDATA%\COWebs.lb\Setup\logs`

The temporary payload is removed after success or failure unless `--keep-temp` is supplied.

## Other operating systems

macOS, Ubuntu, and Fedora adapters are architectural placeholders in v6.0.0 and are not yet runnable. The schema-v2 intent is cross-platform, but the current package mappings and tested execution path are Windows-only.
