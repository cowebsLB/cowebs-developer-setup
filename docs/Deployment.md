# Deployment

## Build

```powershell
./scripts/build-release.ps1
```

The current branch defaults to the next prerelease identity and produces `dist/cowebs-developer-setup-v6.2.0-dev.zip`. Published identities are immutable: the builder refuses `6.0.0` and `6.1.0` from newer source. To reproduce a published asset, check out its release tag. The published v6.1.0 hash remains `0CE008E61DAE7EA26989E6C6528A251D4BE825DEDFFFB286933BB2F9BB00AE46`.

## Published release

Version 6.1.0 is published at `https://github.com/cowebsLB/cowebs-developer-setup/releases/tag/v6.1.0` from source commit `5f78f55351baf963abdf969229363344c6d305a6`.

Published assets:

- `master-setup.bat`
- `cowebs-developer-setup-v6.1.0.zip`

The public ZIP SHA-256 is `0CE008E61DAE7EA26989E6C6528A251D4BE825DEDFFFB286933BB2F9BB00AE46`. The public BAT SHA-256 is `2B1233D1A83CEFAF0E160474F29A2953B039C147F4676F82AB06140A95A933BB`.

The public latest-release BAT downloaded and completed an Everything dry-run with 55 planned packages and zero failures. GitHub Actions validation run `31130931504` passed against the source commit. The push-triggered run did not appear, so the same checked-in workflow was dispatched manually and completed successfully.

## Release procedure

For the next release, replace `NEXT_VERSION` below with a new semantic version that has not been published.

1. Run the complete test suite.
2. Build the minimal release ZIP.
3. Update `EXPECTED_SHA256` in `master-setup.bat` with the printed hash.
4. Normalize `master-setup.bat` to Windows CRLF.
5. Rerun the complete test suite using the final bundle.
6. Confirm the bootstrap integration test passes with its restricted PowerShell module path.
7. Validate all exact Winget IDs against the live source.
8. Commit and push the validated source.
9. Create tag and GitHub release `vNEXT_VERSION`.
10. Upload the ZIP and `master-setup.bat` as release assets.
11. Download the public BAT and run a remote Everything dry-run.
12. Verify GitHub Actions and release asset checksums.

Future platform releases should add their runtime files to the release bundle without changing the shared logical profile contract.

## Architecture-migration artifacts

Schema-v3 catalogs produced by `scripts/convert-catalog-v2-to-v3.ps1` and the Go CLI under `cmd/cowebs-setup` are development artifacts and are intentionally excluded from the v6.1 release ZIP. Planner parity is proven, and the Windows adapter, canonical-plan broker, journal, resume, status, and doctor paths have non-installing coverage; none has replaced the production engine. A future release pipeline will generate platform binaries, a versioned release manifest, checksums, signatures, and software-bill-of-materials files from one version source. That pipeline must not replace the current pinned BAT until a controller performs the one-shot `RunAs` handoff and real Windows installs pass in a disposable VM.
