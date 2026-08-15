# Deployment

## Build

```powershell
./scripts/build-release.ps1
```

The current branch defaults to the next prerelease identity and produces `dist/cowebs-developer-setup-v6.3.0-dev.zip`. Published identities are immutable: the builder refuses `6.0.0`, `6.1.0`, and `6.2.0` from newer source. To reproduce a published asset, check out its release tag.

## Published release

Version 6.2.0 is published at `https://github.com/cowebsLB/cowebs-developer-setup/releases/tag/v6.2.0` from source commit `19fbf0effce030edfc91987debd5090975f918cd`.

Published assets:

- `master-setup.bat`
- `cowebs-developer-setup-v6.2.0.zip`

The public ZIP SHA-256 is `EEE8EAEBC2328E922F34B18C727A6F1408D4A586BE890B87764CAA22E8BD26B3`. The public BAT SHA-256 is `32903AE82D5AE228A0B2F7EFD7BFFDB9FE0790E95F0C604069BADE37388FBFD1`.

GitHub Actions validation run `31326261752` passed against the release source commit. GitHub's recorded SHA-256 digests match the local assets, and independently downloaded public assets reproduced both hashes. The downloaded public BAT completed an Everything dry-run with 55 planned packages and zero failures.

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

Cross-platform preview builds use `scripts/build-cross-platform.ps1`. It compiles the schema-v3 catalogs, builds `cowebs` for Windows x64 and Linux x64/arm64 from one version, creates versioned archives, injects exact archive hashes into the Unix bootstrap, writes `release-manifest-v1.json`, `SHA256SUMS`, an SPDX 2.3 SBOM, and generated Winget manifests. Linux-native packages are built with `scripts/build-linux-packages.sh VERSION ARCH BUNDLE [all|deb|rpm]`; selecting one format keeps Ubuntu and Fedora builders independent. Guarded Ubuntu 24.04 run `31851004282` and Fedora 44 VM run `31852156303` installed and verified the generated DEB/RPM, completed the core real setup, reproduced the canonical plan, verified user state ownership, resumed completed state, and passed a second idempotent run.

The signed release-candidate path is `.github/workflows/release-cross-platform-preview.yml`. For an immutable `vN.N.N-rc.N` tag on `main`, it reruns the full source suite, builds archives plus DEB/RPM, finalizes checksum/SBOM/manifest coverage, keylessly signs every top-level release file, generates GitHub provenance, creates a draft prerelease, verifies authenticated downloads, publishes it, and repeats byte/signature/bootstrap/runtime checks through public unauthenticated downloads. `scripts/finalize-cross-platform-release.ps1` is the deterministic local contract for package inclusion and tag-bound signature metadata.

Version v6.3.0-rc.1 was published as a prerelease from commit `1b85f691dc85d0ad65999dd5b49bd8627a4d4458`. Normal CI `31856222715`, Ubuntu matrix `31856228013`, Fedora VM matrix `31856229843`, signed release workflow `31856640404`, and post-publication documentation CI `31857144843` passed. GitHub lists 18 public assets: nine release files and nine matching Sigstore bundles. An independent unauthenticated audit reproduced all eight manifest-declared artifact sizes and hashes and verified GitHub provenance for the manifest and DEB. Stable v6.2.0 remains the `latest` release. See the [release ledger](releases/6.3.0-rc.1.md) for every filename, size, digest, and verification command.

Do not create the tag until the Ubuntu and Fedora `matrix` jobs and normal CI pass on the exact commit. Tags are never moved after publication; a corrected build uses the next release-candidate number. The stable v6.2.0 Windows assets and `latest` status remain unchanged. Native APT/DNF repository publication, Windows runtime cutover, and stable Linux promotion are separate decisions.

## Architecture-migration artifacts

Schema-v3 catalogs and `cmd/cowebs` remain preview artifacts and are intentionally excluded from the v6.2 release ZIP. The cross-platform pipeline, immutable manifest, checksums, SBOM, Winget metadata, Debian/RPM definitions, Unix bootstrap, Sigstore signing, provenance, and draft/public verification are contract-tested. The Windows BAT must not switch payloads until the separate Go `RunAs` controller and disposable Windows evidence pass. See `docs/support-matrix.md` for the exact evidence boundary.
