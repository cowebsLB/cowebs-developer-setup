# Project instructions

- Preserve `master-setup.bat` as the single-file Windows user experience.
- Never execute mutable default-branch code from a bootstrap; use pinned release assets with verified hashes.
- Keep logical package and profile intent in `config/`; keep package-manager and OS behavior in `src/<platform>/`.
- New adapters must consume shared logical keys and must not fork profile definitions without a documented platform exception.
- Schema-v2 package dependencies and conflicts must reference known logical keys; conflicts must remain symmetric, and role-specific additions should be modeled as reusable packs rather than copied package lists.
- Windows estimate-policy overrides must reference known package keys, remain conservative ranges, and be documented as planning guidance rather than exact installer measurements.
- Real Windows installation runs must use the bootstrap's single `RunAs` handoff and an elevated engine; preview, help, version, and pack-listing paths must remain unelevated.
- Run `tests/run-tests.ps1` after manifest, bootstrap, Windows engine, build, or documentation-contract changes.
- Real installation tests belong in a disposable VM or sandbox, not on a developer's active workstation.
- Never log credentials, authentication output, cookies, keys, or tokens.
- Update README, CHANGELOG, relevant docs, and the current dated worklog for completed changes.
