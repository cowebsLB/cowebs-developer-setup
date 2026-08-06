# CLI and Manifest API

## Windows bootstrap CLI

```text
master-setup.bat [options]
```

- `--profile NAME`: Select `backend`, `frontend`, `android`, `devops`, `ai`, `cyber`, `game`, `fullstack`, or `everything`.
- `--dry-run`: Preview without changes; implies no configuration and no restart.
- `--no-config`: Skip optional post-install configuration.
- `--no-restart`: Suppress the restart prompt.
- `--keep-temp`: Retain the verified extracted payload for debugging.
- `--version`: Print the bootstrap version.
- `--help` or `-h`: Print help without downloading the payload.

Exit codes: `0` success, `1` package failure, `2` argument error, `3` missing runtime prerequisite, `4` temporary-directory failure, `5` download/checksum/extraction failure, and `6` invalid payload structure.

## Package manifest

Every package requires a unique `key`, display `name`, and one or more platform mappings. Windows mappings require an exact `wingetId`. Optional `configure` values connect packages to platform-specific post-install actions.

## Profile manifest

Every profile has a display `name`, a `packages` array of logical keys, and an optional `extends` array. Cycles and unknown references are invalid. Adapters must de-duplicate inherited packages.

There is no network service API.
