# Deployment

## Build

```powershell
./scripts/build-release.ps1
```

The v6.2.0 release source produces `dist/cowebs-developer-setup-v6.2.0.zip`. Published identities are immutable: the builder refuses `6.0.0` and `6.1.0` from newer source. After publication, check out the release tag to reproduce v6.2.0; development on `main` must advance to the next prerelease identity.

## Version 6.2.0 release candidate

The release candidate contains these two assets:

- `master-setup.bat`
- `cowebs-developer-setup-v6.2.0.zip`

The candidate ZIP SHA-256 is `EEE8EAEBC2328E922F34B18C727A6F1408D4A586BE890B87764CAA22E8BD26B3`. The candidate BAT SHA-256 is `32903AE82D5AE228A0B2F7EFD7BFFDB9FE0790E95F0C604069BADE37388FBFD1`.

Publication evidence, source commit, GitHub Actions run, public asset digests, and the downloaded public Everything dry-run are recorded after the release is published and independently downloaded.

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

Schema-v3 catalogs produced by `scripts/convert-catalog-v2-to-v3.ps1` and the Go CLI under `cmd/cowebs-setup` are development artifacts and are intentionally excluded from the v6.2 release ZIP. Planner parity is proven, and the Windows adapter, canonical-plan broker, journal, resume, status, and doctor paths have non-installing coverage; none has replaced the production engine. A future release pipeline will generate platform binaries, a versioned release manifest, checksums, signatures, and software-bill-of-materials files from one version source. That pipeline must not replace the current pinned BAT until a controller performs the one-shot `RunAs` handoff and real Windows installs pass in a disposable VM.
