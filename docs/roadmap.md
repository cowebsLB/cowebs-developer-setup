# Roadmap

## Architecture modernization

- [x] Accept the Go-core, least-privilege broker, provider-aware schema, and structured-journal ADRs.
- [x] Add JSON Schema contracts for package catalog v3, profile catalog v3, execution plans, execution events, and release manifests.
- [x] Add a deterministic and compatibility-tested schema-v2 to schema-v3 compiler.
- [x] Implement a shadow-mode Go planner and prove parity for all profiles, packs, dependencies, conflicts, and estimates.
- [x] Add a clear description for every package before installation.
- [x] Add per-package skipping after installed-package detection and an unattended bootstrap option.
- [x] Implement the Windows provider adapter and one-shot privileged broker.
- [x] Add structured journal, resume, status, doctor, and JSON-output commands.
- [x] Implement the shell-free Ubuntu/Fedora adapter foundation for APT, DNF, Snap, and Flatpak.
- [ ] Switch the generated Windows BAT only after disposable-VM parity and installation validation.

## Next platform milestones

1. Ubuntu APT/Snap/Flatpak mappings, unsupported-package reporting, and disposable-environment adapter integration tests.
2. Fedora DNF/Snap/Flatpak mappings, unsupported-package reporting, and disposable-environment adapter integration tests.
3. macOS Homebrew mappings, shell bootstrap, and adapter tests.

## Cross-platform improvements

- Editor integration for the checked-in JSON Schema files.
- Platform-aware package exclusions and alternatives.
- Per-platform mappings for all schema-v2 packages and explicit unsupported-package reporting.
- Shared configuration intents with platform-specific implementations.
- Release signing and published checksums.
- [x] Resumable setup state for interrupted installations.
- Clean VM/sandbox installation matrix.

Windows real-install validation in a disposable VM remains the immediate release-quality follow-up after v6.2.0 dry-run and live-ID validation. Before runtime cutover, the Go controller must also own the single `RunAs` handoff instead of expecting the broker to be launched elevated.
