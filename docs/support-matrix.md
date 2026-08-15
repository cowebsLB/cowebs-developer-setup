# Support and validation matrix

This matrix separates production support, real disposable evidence, and planning/artifact compatibility. A compiled artifact is not automatically a supported real-install target.

| Platform | Architecture | Public channel | Evidence | Status |
| --- | --- | --- | --- | --- |
| Windows 10/11 and Server 2016+ | x64 | Stable v6.2 `master-setup.bat` | Schema-v2 PowerShell runtime, live Winget identity validation, CI and public dry-run | Production Windows path |
| Windows | x64 | v6.3.0-rc.1 archive | Go binary build and dry-run contracts only | Preview; real Go runtime cutover blocked |
| Ubuntu 24.04 | x64 | v6.3.0-rc.1 archive and DEB | Real native-package/core installation, ownership, resume and idempotency passed in guarded run `31851004282`; expanded failure matrix must pass before publication | Release-candidate target |
| Ubuntu 24.04 | arm64 | v6.3.0-rc.1 archive | Deterministic planning and cross-compilation only | Experimental; no real installation evidence |
| Fedora 43 | x64 | v6.3.0-rc.1 archive and RPM compatibility | Official repository/Snap/Flathub validation and Fedora CI adapter tests | Preview; no full Fedora 43 VM installation |
| Fedora 44 | x64 | v6.3.0-rc.1 archive and RPM | Real Fedora VM native-package/core installation, DNF/Snap, ownership, resume, idempotency and cleanup passed in guarded run `31852156303`; expanded failure matrix must pass before publication | Release-candidate target |
| Fedora 43-44 | arm64 | v6.3.0-rc.1 archive | Official repository metadata, Snap/Flathub identity validation, deterministic planning and cross-compilation | Experimental; no real installation evidence |
| macOS | any | None | Placeholder documentation only | Unsupported |

## Provider coverage

- Ubuntu: 54 executable providers and 32 explicit unsupported results across 86 shared logical keys.
- Fedora: 42 executable providers and 44 explicit unsupported results across the same keys.
- Exact unsupported results are intentional. The planner fails closed instead of substituting a different version, unofficial repository, or arbitrary installer command.

## Release-candidate boundaries

- The supported real Linux entry point is the `cowebs` CLI on matching Ubuntu/Fedora hosts. Real installations must still be trialed in disposable environments before use on a workstation.
- The v6.3.0-rc.1 DEB and RPM are x64 packages. The Linux arm64 archive is planning/artifact evidence only.
- Sigstore bundles authenticate GitHub release-candidate files and GitHub attestations prove build provenance. They are not native APT repository `Release` signatures or RPM repository metadata signatures.
- The Windows archive does not replace `master-setup.bat`; Windows Go execution remains gated.
