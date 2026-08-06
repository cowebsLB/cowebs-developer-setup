# Deployment

## Build

```powershell
./scripts/build-release.ps1 -Version 6.0.0
```

The command produces `dist/cowebs-developer-setup-v6.0.0.zip` and prints its SHA-256. The current local release candidate hash is `FE420680AB209531D19756E3194D625D64607650A98FFA40D4C7F72F3EBC4644`.

## Release procedure

1. Run the complete test suite.
2. Build the minimal release ZIP.
3. Update `EXPECTED_SHA256` in `master-setup.bat` with the printed hash.
4. Normalize `master-setup.bat` to Windows CRLF.
5. Rerun the complete test suite using the final bundle.
6. Confirm the bootstrap integration test passes with its restricted PowerShell module path.
7. Validate all exact Winget IDs against the live source.
8. Commit and push the validated source.
9. Create tag and GitHub release `v6.0.0`.
10. Upload the ZIP and `master-setup.bat` as release assets.
11. Download the public BAT and run a remote Everything dry-run.
12. Verify GitHub Actions and release asset checksums.

Future platform releases should add their runtime files to the release bundle without changing the shared logical profile contract.
