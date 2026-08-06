# Project instructions

- Preserve `master-setup.bat` as the single-file Windows user experience.
- Never execute mutable default-branch code from a bootstrap; use pinned release assets with verified hashes.
- Keep logical package and profile intent in `config/`; keep package-manager and OS behavior in `src/<platform>/`.
- New adapters must consume shared logical keys and must not fork profile definitions without a documented platform exception.
- Run `tests/run-tests.ps1` after manifest, bootstrap, Windows engine, build, or documentation-contract changes.
- Real installation tests belong in a disposable VM or sandbox, not on a developer's active workstation.
- Never log credentials, authentication output, cookies, keys, or tokens.
- Update README, CHANGELOG, relevant docs, and the current dated worklog for completed changes.
