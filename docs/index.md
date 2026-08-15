# Documentation

## Current release boundary

- Stable: Windows v6.2.0 through `master-setup.bat`, schema v2, and the PowerShell engine.
- Prerelease: signed cross-platform v6.3.0-rc.1 `cowebs` archives plus Ubuntu x64 DEB and Fedora x64 RPM.
- Verified source: tag `v6.3.0-rc.1` resolves to `1b85f691dc85d0ad65999dd5b49bd8627a4d4458`.
- Publication evidence: normal CI `31856222715`, Ubuntu matrix `31856228013`, Fedora VM matrix `31856229843`, signed release workflow `31856640404`, and post-release documentation CI `31857144843` passed.
- Boundaries: Windows Go runtime cutover, stable Linux promotion, native package repositories, macOS, and an optional GUI remain future work.

Historical worklogs and ADR context are chronological records. When an older entry says a release gate was pending, the current roadmap, support matrix, testing page, and release notes provide the superseding status.

## Pages

- [Architecture](architecture.md)
- [Architecture Decision Records](adr/README.md)
- [Installation](installation.md)
- [Troubleshooting](troubleshooting.md)
- [Features](features.md)
- [Package and profile selection](package-selection.md)
- [Roadmap](roadmap.md)
- [CLI API](API.md)
- [Go module](../go.mod)
- [Database](Database.md)
- [Security](Security.md)
- [Testing](Testing.md)
- [Deployment](Deployment.md)
- [Support and validation matrix](support-matrix.md)
- [Release notes](releases/6.3.0-rc.1.md)
- [Worklogs](worklogs/)
