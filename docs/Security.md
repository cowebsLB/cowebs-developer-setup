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

- SHA-256 protects the stable v6.2 BAT payload relative to the downloaded BAT; a separately approved stable Windows signing/cutover design is still required. The v6.3.0-rc.1 cross-platform files use Sigstore identity bundles and GitHub provenance as described below.
- Package manifests and upstream installers remain external dependencies.
- Endpoint security or user cancellation can block the one-time elevated handoff; this returns exit code `7` without attempting an elevation bypass.
- Catalog validation proves current Winget discovery, not that all 86 installers were executed on the active workstation.
- Users should obtain the BAT only from the official GitHub release or COWebs.lb site.

## Development least-privilege implementation

The accepted redesign moves download, checksum verification, archive extraction, inventory, planning, and user configuration outside the elevated boundary. The shadow planner strictly rejects unknown catalog fields and emits only typed provider operations bound to a catalog digest. The development Windows broker reloads the verified catalogs, regenerates and requires an exact canonical plan, constructs Winget argument arrays without a shell, refuses real execution without an elevated Windows token, and rejects catalog or operation tampering before mutation. Structured events contain logical identifiers, status, and exit codes but never raw Winget output.

Journal and state inputs remain untrusted files. Event decoding rejects unknown fields and invalid schema vocabulary, sequences must increase, snapshots are flushed before atomic replacement, and resume requires matching plan, catalog, platform, architecture, profile, and operation inventory. Corrupt or legacy partial state fails closed rather than repeating the whole plan.

The Go controller/broker remains a preview path. It has not replaced the v6.2 bootstrap or PowerShell engine and is excluded from the stable runtime ZIP. Linux performs one direct-argument `sudo` handoff for canonical machine operations and keeps user operations outside elevation. The elevated child has its own Unix process group; the parent forwards Ctrl+C to the group and applies a ten-second bounded hard-stop before deferred cleanup, so a package-manager descendant cannot outlive the controller indefinitely. The journal remains resumable and temporary canonical-plan files are removed. Windows Go `RunAs` and disposable Windows validation remain separate cutover blockers.

The Linux adapter follows the same no-shell boundary: catalog fields become individual process arguments, and APT, DNF, Snap, and system Flatpak operations require explicit `elevated`/`machine` metadata. Per-user Flatpak operations require `user`/`user` and an explicit remote. Distribution mismatches, option-shaped identifiers, malformed options, control characters, unsafe paths, credential-bearing URLs, and hash mismatches fail before mutation. Repository keys are bounded to 10 MiB, verified by SHA-256, and written atomically beneath `/etc/apt/keyrings`; APT source files are constrained beneath `/etc/apt/sources.list.d`. APT and DNF metadata refresh once per canonical plan. Missing Snap or Flatpak managers are installed only through hard-coded native package identities; Snap activation and user-scoped Flathub setup remain typed operations rather than catalog commands or shell snippets. Elevated child events are validated and flushed into the initiating user's journal as they arrive, preserving completed-operation evidence if a later package fails. Version mismatches, Windows-only intent, network-script installers, local artifacts, interactive setup, and unavailable desktop products remain explicit unsupported results. GitHub, AWS, and Azure authentication, license activation, Vault initialization, capture permissions, game-engine modules, and tunnel configuration remain manual and are never persisted in catalogs or logs.

Release candidates use Sigstore keyless blob signing from the tag-triggered GitHub Actions workflow, so no long-lived private signing key is stored in the repository or workflow. Verification pins issuer `https://token.actions.githubusercontent.com` and exact workflow identity `https://github.com/cowebsLB/cowebs-developer-setup/.github/workflows/release-cross-platform-preview.yml@refs/tags/v6.3.0-rc.1`; the manifest requires the same immutable identity and rejects mutable raw-GitHub branch URLs. GitHub artifact attestations separately bind release subjects to the repository workflow. These controls authenticate release blobs, including DEB and RPM files, but do not claim native APT repository metadata signing or RPM repository/package-key enrollment.

For v6.3.0-rc.1, release workflow `31856640404` signed all nine release files, generated provenance, verified the private draft, published it, and repeated checksum, signature, bootstrap, runtime, and catalog checks through unauthenticated downloads. A separate public audit reproduced every manifest-declared size and SHA-256 and verified provenance for the manifest and DEB. This satisfies the prerelease integrity gate; stable Linux promotion still requires an explicit product decision and does not imply native repository signing.
