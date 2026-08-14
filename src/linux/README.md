# Linux platform

The source-only Go implementation supports canonical Ubuntu and Fedora plans through `internal/adapter/linux`, `internal/application`, and the public preview `cowebs` CLI. It invokes APT, DNF, Snap, or Flatpak directly without a command shell and validates every platform, privilege, scope, source, package identifier, and typed option before execution.

Ubuntu has 86 reviewed classifications: 54 executable providers and 32 explicit unsupported results. Fedora reuses the same logical keys and profiles through `config/fedora-packages.json`, with 42 executable providers and 44 explicit unsupported results after live Fedora 43/44, Snapcraft, and Flathub validation. The deterministic compatibility compiler is the only producer of schema-v3 runtime catalogs.

The Linux execution path now provides:

- verified SHA-256 repository-key downloads and atomic constrained APT source writes;
- one APT or DNF metadata refresh per plan when required;
- typed native installation of missing Snap/Flatpak managers, Snap service activation, and scoped Flathub remote prerequisites;
- one controller-owned `sudo` handoff for machine operations while user Flatpak and configuration operations remain unelevated;
- Linux-specific Git, Git LFS, VS Code, and Node configuration handlers;
- explicit manual status for GitHub, AWS, and Azure authentication;
- canonical-plan regeneration, streaming redacted JSONL events, atomic state, status, and failure-safe resume;
- distribution, architecture, manager, Flathub, workspace, and catalog diagnostics.

`src/linux/install.sh` is a release template. `scripts/build-cross-platform.ps1` replaces every token with a versioned release URL and exact x64/arm64 digest. It never downloads mutable default-branch code. Debian, RPM, and Winget packaging definitions are available under `packaging/`.

This remains a source preview, not a published stable Linux release. Real installations must run only through `scripts/validate-linux-disposable.sh` in an explicitly authorized disposable VM or ephemeral CI runner. Local disposable validation proved Debian and RPM construction/installation plus the Fedora DNF, snapd activation, failure journaling, and resume boundary. Docker Desktop's kernel cannot mount the current VS Code Snap because it lacks SquashFS LZO support, so full Fedora Snap evidence still requires the guarded LXD/system-container workflow or a disposable VM. Signing, public package-repository publication, downloaded-public-asset verification, and the complete release-candidate matrix remain release gates.
