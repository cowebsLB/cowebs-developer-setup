# Troubleshooting

## Winget is unavailable

Install or update Microsoft App Installer, open a new terminal, and run `winget --version`.

## The release payload cannot be downloaded

Confirm that GitHub Releases is reachable and that v6.1.0 is published at the official `cowebsLB/cowebs-developer-setup` repository. The bootstrap intentionally does not fall back to `main`.

## Checksum mismatch

Do not bypass the check. Delete the downloaded BAT and obtain a fresh copy from the official v6.1.0 release. A mismatch means the BAT and ZIP do not belong to the same release or the payload changed.

## GitHub Actions reports that Get-FileHash is unavailable

This affected the v5 bootstrap when Windows PowerShell inherited a restricted module path from `pwsh`. Version 6 uses .NET APIs for download, hashing, and extraction and does not require `Get-FileHash`, `Invoke-WebRequest`, or `Expand-Archive`. Upgrade the BAT instead of changing the runner to allow an insecure Node version or weakening checksum verification.

## Two selected packs conflict

The engine rejects incompatible plans before installation. For example, the default AI profile uses the modern `uv` environment and cannot be combined with `ai-conda`. Choose one strategy:

```bat
master-setup.bat --profile ai --dry-run
master-setup.bat --profile ai --essentials-only --pack ai-conda --dry-run
```

## A pack name is unknown

Run `master-setup.bat --list-packs` and use the exact lowercase pack key. Repeat `--pack NAME` to add more than one.

## A package fails

Review `master-setup.log`, then confirm the package independently with:

```bat
winget search --id PACKAGE_ID --exact --source winget
```

The Windows engine continues through remaining packages and exits with code `1` if any package fails.

## The estimate differs from the real download or duration

Estimates are conservative fresh-setup planning ranges, not measurements from Winget. Already-installed packages and cached installers reduce them. Package updates, network speed, disk performance, elevation prompts, restarts, and optional components can increase them. Downloads performed later by Android Studio, Unity, Epic Games Launcher, Ollama models, VS Code extensions, or similar tools are not included.

## A newly installed command is unavailable

The script refreshes PATH before optional configuration. Some installers still require a new terminal or Windows restart before their commands become available. The configuration step will warn and skip a missing command.

## Windows asks for Administrator approval repeatedly

Start the installation through `master-setup.bat`, not `src\windows\setup.ps1` directly. A real bootstrap run should show one UAC request and then `Privilege: Administrator`. If it shows `Standard user`, the elevation handoff did not complete; approve the prompt and check whether endpoint security blocked the elevated child process.

Vendor-owned license, driver, account, or configuration dialogs are not Windows privilege prompts and may still appear. Do not disable UAC or change the system consent policy to hide them. If repeated Windows UAC prompts continue after the setup reports Administrator privilege, retain the log with `--keep-temp` and report the affected package name.

## Network warning despite working internet

The lightweight check uses ICMP against GitHub, which some networks block. It is advisory; Winget remains the authoritative connectivity check.

## Review without making changes

Use `--dry-run`. The bootstrap still downloads and verifies its small runtime payload, but the engine skips Winget, logging, configuration, folder creation, and restart behavior.

## The COWEBS banner does not render correctly

Use Windows Terminal or another console with Unicode and box-drawing glyph support. The script selects UTF-8 code page 65001 while running and restores the previous code page when it exits; very old console hosts or fonts may still lack the required glyphs.

## Temporary payload debugging

Use `--keep-temp` to retain the exact extracted session directory. Remove that printed directory manually after diagnosis; do not recursively delete the broader `%TEMP%\COWebs.lb` root.
