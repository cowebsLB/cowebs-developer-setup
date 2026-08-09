# Project instructions

- Preserve `master-setup.bat` as the single-file Windows user experience.
- Never execute mutable default-branch code from a bootstrap; use pinned release assets with verified hashes.
- Keep logical package and profile intent in `config/`; keep package-manager and OS behavior in `src/<platform>/`.
- New adapters must consume shared logical keys and must not fork profile definitions without a documented platform exception.
- Schema-v2 package dependencies and conflicts must reference known logical keys; conflicts must remain symmetric, and role-specific additions should be modeled as reusable packs rather than copied package lists.
- Schema v2 remains the production runtime source until a separately approved runtime cutover; schema-v3 development artifacts must be produced by the deterministic compatibility compiler and must not be hand-maintained as a second source of truth.
- Go planner changes must preserve black-box parity with the PowerShell planner across every profile in default and essentials-only modes, explicit packs, conflicts, estimates, and deterministic output.
- Schema-v3 provider mappings must declare privilege and scope, use typed installer-option arrays, and must never embed arbitrary command or shell fields in catalog or execution-plan data.
- Windows estimate-policy overrides must reference known package keys, remain conservative ranges, and be documented as planning guidance rather than exact installer measurements.
- Real Windows installation runs must use the bootstrap's single `RunAs` handoff and an elevated engine; preview, help, version, and pack-listing paths must remain unelevated.
- Run `tests/run-tests.ps1` after manifest, bootstrap, Windows engine, build, or documentation-contract changes.
- Real installation tests belong in a disposable VM or sandbox, not on a developer's active workstation.
- Never log credentials, authentication output, cookies, keys, or tokens.
- Update README, CHANGELOG, relevant docs, and the current dated worklog for completed changes.
