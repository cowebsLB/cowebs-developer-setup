# Deployment

## Build

```powershell
./scripts/build-release.ps1 -Version 6.1.0
```

The command produces `dist/cowebs-developer-setup-v6.1.0.zip` and prints its SHA-256. The current local release candidate hash is `0CE008E61DAE7EA26989E6C6528A251D4BE825DEDFFFB286933BB2F9BB00AE46`.

## Published release

Version 6.1.0 is published at `https://github.com/cowebsLB/cowebs-developer-setup/releases/tag/v6.1.0` from source commit `5f78f55351baf963abdf969229363344c6d305a6`.

Published assets:

- `master-setup.bat`
- `cowebs-developer-setup-v6.1.0.zip`

The public ZIP SHA-256 is `0CE008E61DAE7EA26989E6C6528A251D4BE825DEDFFFB286933BB2F9BB00AE46`. The public BAT SHA-256 is `2B1233D1A83CEFAF0E160474F29A2953B039C147F4676F82AB06140A95A933BB`.

The public latest-release BAT downloaded and completed an Everything dry-run with 55 planned packages and zero failures. GitHub Actions validation run `31130931504` passed against the source commit. The push-triggered run did not appear, so the same checked-in workflow was dispatched manually and completed successfully.

## Release procedure

1. Run the complete test suite.
2. Build the minimal release ZIP.
3. Update `EXPECTED_SHA256` in `master-setup.bat` with the printed hash.
4. Normalize `master-setup.bat` to Windows CRLF.
5. Rerun the complete test suite using the final bundle.
6. Confirm the bootstrap integration test passes with its restricted PowerShell module path.
7. Validate all exact Winget IDs against the live source.
8. Commit and push the validated source.
9. Create tag and GitHub release `v6.1.0`.
10. Upload the ZIP and `master-setup.bat` as release assets.
11. Download the public BAT and run a remote Everything dry-run.
12. Verify GitHub Actions and release asset checksums.

Future platform releases should add their runtime files to the release bundle without changing the shared logical profile contract.
