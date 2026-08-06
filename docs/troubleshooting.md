# Troubleshooting

## Winget is unavailable

Install or update Microsoft App Installer, open a new terminal, and run `winget --version`.

## The release payload cannot be downloaded

Confirm that GitHub Releases is reachable and that v5.0.0 is still published at the official `cowebsLB/cowebs-developer-setup` repository. The bootstrap intentionally does not fall back to `main`.

## Checksum mismatch

Do not bypass the check. Delete the downloaded BAT and obtain a fresh copy from the official v5.0.0 release. A mismatch means the BAT and ZIP do not belong to the same release or the payload changed.

## A package fails

Review `master-setup.log`, then confirm the package independently with:

```bat
winget search --id PACKAGE_ID --exact --source winget
```

The Windows engine continues through remaining packages and exits with code `1` if any package fails.

## A newly installed command is unavailable

The script refreshes PATH before optional configuration. Some installers still require a new terminal or Windows restart before their commands become available. The configuration step will warn and skip a missing command.

## Network warning despite working internet

The lightweight check uses ICMP against GitHub, which some networks block. It is advisory; Winget remains the authoritative connectivity check.

## Review without making changes

Use `--dry-run`. The bootstrap still downloads and verifies its small runtime payload, but the engine skips Winget, logging, configuration, folder creation, and restart behavior.

## The COWEBS banner does not render correctly

Use Windows Terminal or another console with Unicode and box-drawing glyph support. The script selects UTF-8 code page 65001 while running and restores the previous code page when it exits; very old console hosts or fonts may still lack the required glyphs.

## Temporary payload debugging

Use `--keep-temp` to retain the exact extracted session directory. Remove that printed directory manually after diagnosis; do not recursively delete the broader `%TEMP%\COWebs.lb` root.
