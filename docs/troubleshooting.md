# Troubleshooting

## Winget is unavailable

Install or update Microsoft App Installer, open a new terminal, and run `winget --version`.

## The release payload cannot be downloaded

Confirm that GitHub Releases is reachable and that v6.2.0 is published at the official `cowebsLB/cowebs-developer-setup` repository. The bootstrap intentionally does not fall back to `main`.

## Checksum mismatch

Do not bypass the check. Delete the downloaded BAT and obtain a fresh copy from the official v6.2.0 release. A mismatch means the BAT and ZIP do not belong to the same release or the payload changed.

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

## Linux preview reports unsupported packages

This is fail-closed behavior, not silent omission. The diagnostic lists every selected logical key without a reviewed provider for the target distribution and architecture. Choose a supported profile/pack combination or wait for a reviewed provider; do not replace the catalog entry with a shell command or unverified installer.

## Linux preview reports that Snap, Flatpak, or Flathub is missing

Run `cowebs doctor dev-setup --json`. A selected Snap or Flatpak provider adds a typed elevated prerequisite that installs the reviewed native manager package when missing; Snap activation is handled before package installation, and a selected Flathub package adds the official HTTPS remote through a typed user or machine operation. A failure after that point should be resumed with the saved plan, journal, and state rather than editing the canonical plan.

## Fedora Snap fails inside a container

If the journal reports a Snap mount failure and `journalctl` says the SquashFS image uses unsupported LZO compression, the container is using a host kernel without the required SquashFS codec. This is an environment limitation, not a package retry condition. Move the validation to the guarded Fedora LXD workflow or a disposable Fedora VM with the required kernel support; do not claim container-only results as full Fedora installation evidence.

## Linux plan does not match the current host

Real execution requires the plan's Ubuntu/Fedora target to match `/etc/os-release`. Rebuild the canonical plan for the current distribution. Do not edit the plan JSON: catalog digest and canonical-plan regeneration intentionally reject changes.

## Disposable validation refuses to run

`scripts/validate-linux-disposable.sh` requires `COWEBS_DISPOSABLE=1` and either an ephemeral CI environment or a detected virtualization boundary. Move the test into a disposable VM/sandbox. Do not set the override on an active workstation merely to bypass the guard.

## Update or bootstrap integrity validation fails

Do not bypass URL, size, or SHA-256 validation. The manifest and artifact URLs must use immutable HTTPS release paths, and downloaded bytes must exactly match the declared size and digest. Default-branch URLs are deliberately rejected.

## Linux installation was interrupted

Ctrl+C is forwarded to the elevated installer process group and the canonical temporary plan is cleaned up. The initiating user's journal preserves completed operations. Let any package-manager service change finish, run `cowebs status dev-setup`, then run `cowebs resume dev-setup --non-interactive`. For Snap, `snap changes` shows whether a server-side change is still `Doing`; exit code 10 during an immediate retry means a conflicting Snap change is still in progress, so wait and resume again. Do not delete or edit the journal to force progress.

## Linux installation failed while offline

The failed operation is recorded without raw package-manager output or credentials. Restore network access, run `cowebs status dev-setup`, and then use `cowebs resume dev-setup --non-interactive`. Already-completed operations are skipped after the canonical plan and catalog digest are revalidated.

## `cowebs` is not found after the Unix bootstrap

The bootstrap installs the executable in `$HOME/.local/bin`. Start a new login shell or add it for the current session with `export PATH="$HOME/.local/bin:$PATH"`. Native DEB/RPM packages install `/usr/bin/cowebs` and do not need this user PATH addition.

## Verify a release signature

Download the release file and its matching `.sigstore.json` bundle, then run `cosign verify-blob --bundle FILE.sigstore.json --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity https://github.com/cowebsLB/cowebs-developer-setup/.github/workflows/release-cross-platform-preview.yml@refs/tags/vVERSION FILE`. The identity must match the exact release tag. SHA-256 checksums remain mandatory; signature verification does not replace them.

For v6.3.0-rc.1, replace `vVERSION` with `v6.3.0-rc.1` and use the exact matching bundle name. Compare payload hashes with both `SHA256SUMS` and the [recorded release ledger](releases/6.3.0-rc.1.md). If the checksum, bundle identity, GitHub attestation, declared size, or tag differs, stop: do not execute the file, do not reuse a bundle from another asset or tag, and report the exact filename and failing verification step without posting credentials or authentication output.
