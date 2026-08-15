# Roadmap

## Current baseline

| Area | Status | Runtime boundary |
|---|---|---|
| Windows v6.2.0 | Released and verified | Schema v2 plus `src/windows/setup.ps1` |
| Go planner and schema v3 | Source-only, parity proven | Not included in the public runtime ZIP |
| Windows Go adapter and broker | Source-only, tested | Runtime cutover still gated on real-install validation and controller-owned elevation |
| Ubuntu/Fedora adapter | Complete classification, deterministic planning, and preview execution | Ubuntu 54/32 and live-validated Fedora 42/44 executable/unsupported; Ubuntu 24.04/Fedora 44 x64 matrix evidence passed |
| Public `cowebs` CLI | Signed cross-platform prerelease published | v6.3.0-rc.1 preview; Windows BAT and schema v2 remain production |
| macOS | Planned after the Linux path | No adapter or provider catalog yet |

## Completed architecture foundation

- [x] Accept the Go-core, least-privilege broker, provider-aware schema, and structured-journal ADRs.
- [x] Add JSON Schema contracts for package catalog v3, profile catalog v3, execution plans, execution events, and release manifests.
- [x] Add a deterministic and compatibility-tested schema-v2 to schema-v3 compiler.
- [x] Implement a shadow-mode Go planner and prove parity for all profiles, packs, dependencies, conflicts, and estimates.
- [x] Add a clear description for every package before installation.
- [x] Add per-package skipping after installed-package detection and an unattended Windows bootstrap option.
- [x] Implement the Windows provider adapter and canonical one-shot privileged broker.
- [x] Add structured journal, resume, status, doctor, and JSON-output commands.
- [x] Implement the shell-free Ubuntu/Fedora adapter foundation for APT, DNF, Snap, and Flatpak.
- [x] Publish and publicly verify v6.2.0, then advance development builds to v6.3.0-dev.

## Linux delivery plan

### Phase 1: Typed adapter foundation — complete

- [x] Route Ubuntu operations through APT, Snap, or Flatpak and Fedora operations through DNF, Snap, or Flatpak.
- [x] Build direct argument arrays without a command shell.
- [x] Enforce explicit manager, distribution, privilege, scope, source, package-ID, and installer-option contracts.
- [x] Detect installed packages through dpkg, DNF, Snap, and user/system Flatpak inventories.
- [x] Distinguish residual dpkg configuration from an installed package.
- [x] Cover dry-run isolation, process-start failure, mismatched managers, malformed arguments, and Flatpak scope in unit tests.

### Phase 2: Ubuntu catalog and planning — package classification complete

- [x] Define the deterministic schema-v2 compatibility input for reviewed Ubuntu providers without creating a hand-maintained schema-v3 catalog.
- [x] Classify the 11-package core slice: seven native packages, one documented alternative, two conditional Snap packages, and GitHub CLI through a conditional signed APT repository.
- [x] Classify every logical package as supported, replaced by a documented Linux alternative, conditionally supported, or unsupported on Ubuntu.
- [x] Add exact APT, Snap, or Flatpak provider identifiers, source, privilege, scope, architecture, typed options, and conservative estimates.
- [x] Make the compatibility compiler emit deterministic Ubuntu providers while retaining the Windows provider contract and production runtime behavior.
- [x] Add explicit planner diagnostics that list all unsupported packages for the selected profile instead of failing on only the first missing provider or silently omitting intent.
- [x] Prove the full 11-package Ubuntu x64 core plan through compilation, planning, detection, dry-run rendering, and deterministic JSON.
- [x] Model the official GitHub CLI signed APT repository as typed, digest-pinned catalog data and emit one de-duplicated package-index refresh; keep real mutation disabled pending Phase 4 orchestration.
- [x] Classify the 15-package language/runtime/container slice with native Node.js, OpenJDK 21, .NET SDK 10, and Rustup providers, a conditional Canonical Go snap, and ten explicit unsupported results for unmodeled version, artifact, or user-configuration paths.
- [x] Classify the 14-package database/client/browser/networking/design/Android slice with nine exact providers and five explicit unsupported results; cover PostgreSQL, Chrome, Cloudflare, and ngrok repositories with digest-pinned typed prerequisites.
- [x] Classify the 18-package host-platform/Kubernetes/IaC/automation/secrets slice with eleven exact providers and seven explicit unsupported results; share typed Trivy and HashiCorp repository prerequisites without duplicate refreshes.
- [x] Classify the final 28 cloud/data/security/game packages with eighteen exact providers and ten explicit unsupported results; preserve GIMP 3 through Flathub, limit reviewed x64-only providers explicitly, and add typed Azure CLI, Google Cloud CLI, and Unity Hub repositories.
- [x] Map supported configuration intents to Linux-specific implementations; keep authentication, account, license, and unsupported configuration explicit.
- [x] Validate all 86 classifications, ten keyring digests, Snap/Flathub architecture availability, and repository package indexes against current primary sources without installing on the developer workstation.

### Phase 3: Fedora catalog and planning — complete

- [x] Reuse the same logical keys and provider contract; do not fork profile definitions.
- [x] Classify all packages for Fedora as 42 DNF/Snap/Flatpak providers and 44 explicit unsupported results.
- [x] Emit deterministic Fedora providers from the compatibility compiler.
- [x] Prove the full Fedora core plan plus unsupported profile diagnostics with deterministic-output standards.
- [x] Validate mappings against official Fedora 43/44 x64/arm64 repositories, the Snapcraft API, and Flathub remote metadata without mutating the developer workstation; correct Node.js to `nodejs24` and fail closed for unavailable OpenJDK 21 and scrcpy providers.

### Phase 4: Linux orchestration and least privilege — source implementation complete

- [x] Extend diagnostics to identify the distribution, architecture, available managers, Flatpak/Flathub state, and missing prerequisites.
- [x] Add controller routing for Ubuntu and Fedora while preserving the separate production Windows path.
- [x] Execute user-scoped Flatpak/configuration work without elevation and group machine work behind one direct-argument `sudo` handoff.
- [x] Refresh APT or DNF metadata once per canonical plan when required.
- [x] Model native Snap/Flatpak manager installation, Snap activation, and Flatpak remote setup as typed dependencies rather than arbitrary catalog shell setup.
- [x] Preserve canonical-plan regeneration, catalog digest binding, streaming redacted events, atomic snapshots, resume identity, and fail-closed recovery on Linux.
- [x] Define explicit configuration skipping/manual-authentication, no implicit restart, failure summary, temporary-plan cleanup, and idempotent resume behavior.

### Phase 5: Public COWebs CLI product surface — source implementation complete

- [x] Make `cowebs install dev-setup` the interactive/non-interactive published-preview installation entry point.
- [x] Define the plan, install, status, resume, doctor, and update command family.
- [x] Treat `dev-setup` as a stable product identifier.
- [x] Preserve profile, repeatable pack, essentials-only, dry-run, non-interactive, configuration, restart, and JSON grammar.
- [x] Reuse the planner, broker, journal, resume, status, and doctor packages behind the public CLI.
- [x] Extract a shared Go application/service layer for terminal and future GUI frontends.
- [x] Define help, exit codes, human/JSON output, completions, version, and unknown-product diagnostics.
- [x] Preserve the released Windows BAT and retain `cowebs-setup` as the development compatibility entry point.
- [x] Make update checks/downloads consume only strict immutable HTTPS release manifests and verified artifacts.
- [x] Add parser, dispatch, compatibility, completion, update-integrity, and CLI planning tests.

### Phase 6: Native packaging, bootstrap, and immutable distribution

- [ ] Publish the `cowebs` executable through Winget/MSI or MSIX on Windows, signed `.deb`/APT packages on Ubuntu, signed `.rpm`/DNF packages on Fedora, and Homebrew after macOS support exists.
- [x] Add a thin generated Unix bootstrap that downloads only a versioned `cowebs` artifact and verifies its exact SHA-256.
- [x] Build versioned Windows x64 and Linux x64/arm64 `cowebs` binaries from one version source; publication remains gated.
- [x] Generate a release manifest recording platform, architecture, artifact name, size, digest, and minimum environment.
- [x] Keep the bootstrap free of mutable default-branch execution, repository cloning, credentials, and arbitrary install commands.
- [x] Generate checksums and an SPDX SBOM; v6.3.0-rc.1 release files are signed with tag-bound Sigstore bundles, while stable promotion remains a separate decision.
- [x] Preserve `master-setup.bat` as the released Windows single-file experience.
- [ ] Make the optional native installer a graphical frontend over the same shared controller used by `cowebs install dev-setup`, with identical plans, consent, progress, journal, resume, and failure semantics.

### Phase 7: Disposable-environment validation and Linux release gate

- [x] Configure non-installing compiler, planner, adapter, public-CLI, bootstrap, and disposable dry-run CI coverage for Ubuntu and Fedora.
- [x] Build, install, and package-manager-verify initial unsigned DEB/RPM candidates on Ubuntu 24.04 and Fedora 44; the published v6.3.0-rc.1 package blobs have matching Sigstore bundles, and root ownership and installed modes were verified.
- [x] Prove Fedora DNF installation, native snapd provisioning/activation, user-owned journals, persisted failure state, and resume retry inside a disposable systemd container; do not count the host-kernel SquashFS LZO limitation as full Snap evidence.
- [x] Run core real installations only in disposable Ubuntu and Fedora environments: guarded Ubuntu run `31851004282` and Fedora VM run `31852156303` passed.
- [x] Complete the expanded disposable `matrix` workflow for partially provisioned/skipped packages, forced offline failure/recovery, and active interruption/resume: Ubuntu `31856228013` and Fedora VM `31856229843` passed.
- [x] Verify user-versus-machine ownership, fresh-login PATH, JSON-only/redacted journals, temporary-plan cleanup, and disposable-environment cleanup on both targets in the same runs.
- [x] Define the evidence-based support matrix in `docs/support-matrix.md`; update its release-candidate run references after the expanded matrix completes.
- [x] Publish signed prerelease v6.3.0-rc.1 after public asset hashes, downloaded bootstrap/runtime checks, CI `31856222715`, and disposable installation evidence agreed; release workflow `31856640404` passed.
- [ ] Verify that installation through native packages, the Unix bootstrap, the terminal CLI, and the optional GUI resolves the same canonical `dev-setup` plan for identical inputs.

## Parallel Windows runtime-cutover gates

- [ ] Implement the Go controller's single `RunAs` handoff instead of requiring a pre-elevated broker.
- [ ] Validate every Windows profile and relevant pack through real installation in Windows Sandbox or a disposable VM.
- [ ] Test partial inventory, skip, failure, interruption, resume, configuration, restart, and repeat-run behavior.
- [ ] Prove generated-controller parity with the released BAT/PowerShell runtime before changing the public Windows execution path.
- [ ] Switch the Windows bootstrap payload only through a separately approved release after all cutover evidence passes.

## Cross-platform backlog

- [ ] Add editor integration for the checked-in JSON Schema files.
- [ ] Add platform-aware alternatives and exclusions without duplicating logical profiles.
- [ ] Complete per-platform mappings with explicit unsupported-package reporting.
- [ ] Implement shared configuration intents through platform-specific handlers.
- [x] Add resumable setup state for interrupted installations.
- [x] Add guarded Ubuntu and Fedora disposable validation workflows with native-package installation, canonical-plan parity, interruption/resume, partial inventory, offline recovery, PATH/session, ownership, redaction, cleanup, and idempotency gates; core runs `31851004282`/`31852156303` and expanded runs `31856228013`/`31856229843` passed.
- [x] Publish keyless Sigstore bundles, GitHub provenance, and publicly reverified checksums for v6.3.0-rc.1 in release workflow `31856640404`.
- [ ] Begin the macOS Homebrew adapter and catalog only after the Linux provider/compiler pattern is proven reusable.

## Definition of done

### Linux preview-ready

- Ubuntu and Fedora catalogs compile deterministically.
- Selected plans report complete supported and unsupported intent.
- Detection and dry-run paths execute without elevation or mutation.
- CI covers both distributions and all schema/planner/adapter contracts.
- `cowebs plan dev-setup` exposes the same deterministic plan through documented human and JSON output contracts.

### Linux stable-runtime-ready

- `cowebs install dev-setup` is the documented stable entry point and shares one orchestration implementation with any native GUI.
- The Unix bootstrap is checksum-pinned to immutable artifacts.
- Privilege separation, journal/resume, diagnostics, and configuration behavior pass disposable-environment tests.
- Supported packages and distribution versions are documented from current evidence.
- Public artifacts reproduce their recorded hashes and complete downloaded dry-runs.
- No unresolved high-severity correctness, security, recovery, or release-integrity finding remains.

The Linux prerelease critical path is complete: the expanded Ubuntu/Fedora matrices passed, exact source commit `1b85f691dc85d0ad65999dd5b49bd8627a4d4458` was tagged, and release workflow `31856640404` signed, attested, published, and publicly re-downloaded every v6.3.0-rc.1 file. Remaining roadmap work is deliberately separate: canonical parity through every product surface including a future GUI, native APT/DNF and Windows package-repository publication, stable Linux promotion, macOS support, and the Windows Go runtime cutover gates.
