# Roadmap

## Current baseline

| Area | Status | Runtime boundary |
|---|---|---|
| Windows v6.2.0 | Released and verified | Schema v2 plus `src/windows/setup.ps1` |
| Go planner and schema v3 | Source-only, parity proven | Not included in the public runtime ZIP |
| Windows Go adapter and broker | Source-only, tested | Runtime cutover still gated on real-install validation and controller-owned elevation |
| Ubuntu/Fedora adapter | Source-only foundation complete | No reviewed Linux provider catalog, broker orchestration, or Unix bootstrap yet |
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

### Phase 2: Ubuntu catalog and planning — next

- [ ] Define the deterministic schema-v2 compatibility input for reviewed Ubuntu providers without creating a hand-maintained schema-v3 catalog.
- [ ] Classify every logical package as supported, replaced by a documented Linux alternative, conditionally supported, or unsupported on Ubuntu.
- [ ] Add exact APT, Snap, or Flatpak provider identifiers, source, privilege, scope, architecture, typed options, and conservative estimates.
- [ ] Make the compatibility compiler emit deterministic Ubuntu providers while retaining byte-stable Windows output.
- [ ] Add explicit planner diagnostics that list all unsupported packages for the selected profile instead of failing on only the first missing provider or silently omitting intent.
- [ ] Prove at least one bounded Ubuntu profile/pack plan end to end through compilation, planning, detection, dry-run rendering, and deterministic JSON.
- [ ] Map supported configuration intents to Linux-specific implementations; leave unsupported configuration explicit.
- [ ] Validate provider availability against official Ubuntu, Snap, and Flathub sources without installing on the developer workstation.

### Phase 3: Fedora catalog and planning

- [ ] Reuse the same logical keys and provider contract; do not fork profile definitions.
- [ ] Classify all packages for Fedora and add exact DNF, Snap, or Flatpak mappings with explicit unsupported results.
- [ ] Emit deterministic Fedora providers from the compatibility compiler.
- [ ] Prove a bounded Fedora profile/pack plan with the same parity, diagnostics, estimate, and deterministic-output standards as Ubuntu.
- [ ] Validate mappings against official Fedora, Snap, and Flathub sources without mutating the developer workstation.

### Phase 4: Linux orchestration and least privilege

- [ ] Extend diagnostics to identify the distribution, architecture, available managers, Flatpak installations/remotes, and missing prerequisites.
- [ ] Add controller routing for Ubuntu and Fedora plans while keeping the Windows broker platform-locked.
- [ ] Execute user-scoped Flatpak work without elevation and group machine-scoped work behind one explicit typed privileged handoff.
- [ ] Refresh APT/DNF metadata at most once per session when required; do not repeat repository work per package.
- [ ] Model Snap/Flatpak manager or remote prerequisites as typed dependencies rather than arbitrary shell setup.
- [ ] Preserve canonical-plan regeneration, catalog digest binding, redacted events, atomic snapshots, resume identity, and fail-closed recovery on Linux.
- [ ] Define configuration, restart/session-refresh, failure-summary, and cleanup behavior for Linux.

### Phase 5: Unix bootstrap and immutable distribution

- [ ] Add a thin Unix bootstrap that downloads only a pinned release artifact and verifies its declared SHA-256 before execution.
- [ ] Publish versioned Linux binaries for supported architectures from one version source.
- [ ] Generate a release manifest that records platform, architecture, artifact name, size, digest, and minimum supported environment.
- [ ] Keep the bootstrap free of mutable default-branch execution, repository cloning, credentials, and embedded arbitrary install commands.
- [ ] Add checksums and an SBOM; evaluate signing before declaring the Linux path stable.
- [ ] Preserve `master-setup.bat` as the Windows single-file experience throughout Linux delivery.

### Phase 6: Disposable-environment validation and Linux release gate

- [ ] Run non-installing compiler, planner, adapter, and bootstrap tests in CI for Ubuntu and Fedora.
- [ ] Run real installations only in disposable Ubuntu and Fedora VMs or equivalent isolated environments.
- [ ] Test fresh installation, partially provisioned hosts, already-installed packages, skipped packages, network/source failure, interrupted execution, resume, and a second idempotency run.
- [ ] Verify user-versus-machine ownership, PATH/session behavior, logs, cleanup, and absence of credential or raw installer-output persistence.
- [ ] Record the supported distribution/version/architecture matrix from evidence gathered during the release candidate.
- [ ] Publish a Linux release only after public asset hashes, downloaded bootstrap dry-runs, CI, and disposable-environment installation evidence all agree.

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
- [ ] Maintain a clean VM/sandbox validation matrix.
- [ ] Add release signing, published checksums, release-manifest verification, and SBOM generation.
- [ ] Begin the macOS Homebrew adapter and catalog only after the Linux provider/compiler pattern is proven reusable.

## Definition of done

### Linux preview-ready

- Ubuntu and Fedora catalogs compile deterministically.
- Selected plans report complete supported and unsupported intent.
- Detection and dry-run paths execute without elevation or mutation.
- CI covers both distributions and all schema/planner/adapter contracts.

### Linux stable-runtime-ready

- The Unix bootstrap is checksum-pinned to immutable artifacts.
- Privilege separation, journal/resume, diagnostics, and configuration behavior pass disposable-environment tests.
- Supported packages and distribution versions are documented from current evidence.
- Public artifacts reproduce their recorded hashes and complete downloaded dry-runs.
- No unresolved high-severity correctness, security, recovery, or release-integrity finding remains.

The immediate implementation sequence is Ubuntu compatibility mappings and complete unsupported-package diagnostics, followed by a bounded Ubuntu end-to-end plan. Fedora should reuse that proven path before Linux privilege orchestration and bootstrap work begin.
