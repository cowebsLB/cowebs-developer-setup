# Roadmap

## Current baseline

| Area | Status | Runtime boundary |
|---|---|---|
| Windows v6.2.0 | Released and verified | Schema v2 plus `src/windows/setup.ps1` |
| Go planner and schema v3 | Source-only, parity proven | Not included in the public runtime ZIP |
| Windows Go adapter and broker | Source-only, tested | Runtime cutover still gated on real-install validation and controller-owned elevation |
| Ubuntu/Fedora adapter | Source-only foundation complete | No reviewed Linux provider catalog, broker orchestration, or Unix bootstrap yet |
| Public `cowebs` CLI | Planned product surface | Existing `cowebs-setup` remains the source-only development engine |
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

### Phase 5: Public COWebs CLI product surface

- [ ] Make `cowebs install dev-setup` the stable interactive installation entry point.
- [ ] Define the public command family: `cowebs plan dev-setup`, `cowebs install dev-setup`, `cowebs status dev-setup`, `cowebs resume dev-setup`, `cowebs doctor dev-setup`, and `cowebs update`.
- [ ] Treat `dev-setup` as a stable product identifier so the umbrella CLI can add future COWebs products without changing the setup engine's domain model.
- [ ] Preserve current profile, repeatable pack, essentials-only, dry-run, non-interactive, configuration, restart, and JSON capabilities through the public command grammar.
- [ ] Reuse the existing `cowebs-setup` planner, broker, journal, resume, status, and doctor implementation behind the public CLI until an internal rename or package move passes compatibility tests.
- [ ] Extract a shared Go application/service layer so the terminal CLI and future native GUI call the same typed orchestration API; the GUI must not scrape CLI output or duplicate planning logic.
- [ ] Define stable help text, exit codes, human and JSON output contracts, shell completions, version reporting, and unknown-product/command diagnostics.
- [ ] Preserve compatibility for the released Windows BAT and document any temporary `cowebs-setup` alias before removing or renaming an entry point.
- [ ] Make self-update consume only a verified immutable release manifest; never download or execute mutable default-branch code.
- [ ] Add parser, dispatch, compatibility, completion, update-integrity, and CLI-to-controller end-to-end tests.

### Phase 6: Native packaging, bootstrap, and immutable distribution

- [ ] Publish the `cowebs` executable through Winget/MSI or MSIX on Windows, signed `.deb`/APT packages on Ubuntu, signed `.rpm`/DNF packages on Fedora, and Homebrew after macOS support exists.
- [ ] Add a thin Unix bootstrap that downloads only a pinned `cowebs` release artifact and verifies its declared SHA-256 before execution.
- [ ] Publish versioned `cowebs` binaries for supported platforms and architectures from one version source.
- [ ] Generate a release manifest that records platform, architecture, artifact name, size, digest, and minimum supported environment.
- [ ] Keep the bootstrap free of mutable default-branch execution, repository cloning, credentials, and embedded arbitrary install commands.
- [ ] Add checksums and an SBOM; evaluate signing before declaring the Linux path stable.
- [ ] Preserve `master-setup.bat` as the Windows single-file experience throughout Linux delivery.
- [ ] Make the optional native installer a graphical frontend over the same shared controller used by `cowebs install dev-setup`, with identical plans, consent, progress, journal, resume, and failure semantics.

### Phase 7: Disposable-environment validation and Linux release gate

- [ ] Run non-installing compiler, planner, adapter, and bootstrap tests in CI for Ubuntu and Fedora.
- [ ] Run real installations only in disposable Ubuntu and Fedora VMs or equivalent isolated environments.
- [ ] Test fresh installation, partially provisioned hosts, already-installed packages, skipped packages, network/source failure, interrupted execution, resume, and a second idempotency run.
- [ ] Verify user-versus-machine ownership, PATH/session behavior, logs, cleanup, and absence of credential or raw installer-output persistence.
- [ ] Record the supported distribution/version/architecture matrix from evidence gathered during the release candidate.
- [ ] Publish a Linux release only after public asset hashes, downloaded bootstrap dry-runs, CI, and disposable-environment installation evidence all agree.
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
- [ ] Maintain a clean VM/sandbox validation matrix.
- [ ] Add release signing, published checksums, release-manifest verification, and SBOM generation.
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

The immediate implementation sequence remains Ubuntu compatibility mappings and complete unsupported-package diagnostics, followed by a bounded Ubuntu end-to-end plan. Fedora should reuse that proven path before Linux privilege orchestration begins. The public `cowebs install dev-setup` contract is implemented over the proven shared controller before native packaging, bootstrap, or GUI distribution.
