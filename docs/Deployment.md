# Deployment

## Build

```powershell
./scripts/build-release.ps1 -Version 5.0.0
```

The command produces `dist/cowebs-developer-setup-v5.0.0.zip` and prints its SHA-256.

## Release procedure

1. Run the complete test suite.
2. Build the minimal release ZIP.
3. Update `EXPECTED_SHA256` in `master-setup.bat` with the printed hash.
4. Normalize `master-setup.bat` to Windows CRLF.
5. Rerun the complete test suite using the final bundle.
6. Validate all exact Winget IDs against the live source.
7. Commit and push the validated source.
8. Create tag and GitHub release `v5.0.0`.
9. Upload the ZIP and `master-setup.bat` as release assets.
10. Download the public BAT and run a remote Everything dry-run.
11. Verify GitHub Actions and release asset checksums.

Future platform releases should add their runtime files to the release bundle without changing the shared logical profile contract.
