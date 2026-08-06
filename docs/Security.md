# Security

## Trust boundary

The BAT executes only a release payload whose SHA-256 matches the value embedded in that BAT version. It never clones or executes the mutable default branch.

The bootstrap computes SHA-256 through `System.Security.Cryptography.SHA256` and extracts through `System.IO.Compression.ZipFile`. These APIs avoid dependence on module auto-loading while preserving the same fail-closed checksum boundary.

## Temporary cleanup

Each session creates `%TEMP%\COWebs.lb\setup-<random>-<random>`. Cleanup references the exact constructed session path, never `%TEMP%`, a user profile, repository root, wildcard, or unresolved broad path. `--keep-temp` is an explicit debugging override.

## Credentials and logs

GitHub, AWS, and Azure authentication remain interactive. Logs record outcomes but never passwords, access tokens, cloud keys, authentication cookies, or raw authentication output. Logs are copied nowhere because they are created directly in their persistent location outside the temporary payload.

## Package installation

Windows packages use exact identifiers and the explicit Winget community source. A real installation checks its current access token and requests one standard Windows `RunAs` elevation before downloading or executing the verified payload. The engine independently refuses a real run without Administrator privilege. Preview and informational operations remain least-privileged and do not trigger UAC.

The bootstrap does not disable UAC, change consent policy, cache administrator credentials, or execute as `SYSTEM`. Scalar relaunch arguments are reconstructed from parsed switches, while selected pack keys cross the boundary as environment data and are validated by the engine. Vendor installers remain separate trust boundaries and may still present their own UI.

Schema-v2 dependencies and conflicts are resolved before Winget runs. The bootstrap transfers pack keys through an environment variable instead of adding untrusted values to the generated PowerShell argument string. A real Kali WSL installation requires an explicit confirmation that it will be used only in an authorized lab. Package-specific overrides are fixed manifest data and are covered by review and tests.

## Remaining limitations

- SHA-256 protects payload integrity relative to the downloaded BAT; code signing is planned for stronger publisher identity.
- Package manifests and upstream installers remain external dependencies.
- Endpoint security or user cancellation can block the one-time elevated handoff; this returns exit code `7` without attempting an elevation bypass.
- Catalog validation proves current Winget discovery, not that all 86 installers were executed on the active workstation.
- Users should obtain the BAT only from the official GitHub release or COWebs.lb site.
