# Installation

## Windows requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Winget through Microsoft App Installer for real installation runs
- Internet access to GitHub Releases and the Winget source

Download `master-setup.bat` from the v5.0.0 GitHub release. No repository clone and no preinstalled Git client are required.

Preview first:

```bat
master-setup.bat --profile everything --dry-run
```

Administrator mode is not required for the bootstrap. Winget or individual installers can request elevation when their manifests require it.

## Temporary and persistent files

- Temporary payload: `%TEMP%\COWebs.lb\setup-<random>`
- Persistent logs: `%LOCALAPPDATA%\COWebs.lb\Setup\logs`

The temporary payload is removed after success or failure unless `--keep-temp` is supplied.

## Other operating systems

macOS, Ubuntu, and Fedora adapters are architectural placeholders in v5.0.0 and are not yet runnable.
