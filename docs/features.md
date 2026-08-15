# Features

## Available in v6.2.0

- Full UTF-8 COWEBS.LB block-letter branding
- Single-file Windows user experience
- Pinned and SHA-256-verified release payload
- Nine shared developer profiles
- Eighty-six logical packages with live-verified exact Winget mappings
- Thirty-four reusable use-case packs
- Core, essential, recommended, and optional selection layers
- Recursive dependencies, conflict detection, profile inheritance, and duplicate elimination
- Repeatable CLI pack selection, interactive optional-pack selection, essentials-only mode, and pack listing
- Package tier, category, license, condition, and installer-strategy metadata
- Interactive and CLI-driven execution
- One-time UAC elevation for complete real installations, with prompt-free previews and visible privilege state
- Installation, skip, failure, and dry-run summaries
- Fresh-setup download and install-time estimate ranges
- Color-coded installing, success, skipped, failed, and planned status labels
- Final installed/skipped/failed counts, configured-component inventory, and log location
- Optional Git, Git LFS, GitHub CLI, VS Code, Node.js, Python/uv, Docker, AWS, and Azure configuration
- Authorized-lab confirmation for Kali WSL and package-specific Visual Studio game workload installation
- Persistent secret-free logging
- Scoped temporary cleanup
- Automated release-building and bootstrap simulation
- Detailed package descriptions covering function, operation, and use case for all catalog packages
- Interactive package skipping after installed-package detection, with `>skip`/`skip`/`s` responses and a bootstrap `--non-interactive` override

## Platform status

| Platform | Status | Planned package manager |
|---|---|---|
| Windows | Implemented | Winget |
| macOS | Planned | Homebrew |
| Ubuntu 24.04 x64 | Preview planning and least-privilege execution; core disposable install passed | Eighty-six classifications: fifty-four executable providers and thirty-two explicit unsupported results |
| Fedora 44 x64 | Preview planning and least-privilege execution; core disposable VM install passed | Eighty-six classifications: forty-two executable providers and forty-four explicit unsupported results |

## Development architecture modernization (source-only in v6.2.0)

- Provider-aware package and profile schemas for the future cross-platform core
- Typed execution-plan, event, and release-manifest contracts
- Deterministic schema-v2 to schema-v3 compatibility compiler
- Typed Ubuntu compatibility input for native, alternative, conditional, and unsupported classifications
- Separate reviewed Fedora compatibility input over the same logical keys and shared profiles
- All eighty-six logical packages have reviewed Ubuntu classifications, with fifty-four executable providers and thirty-two explicit unsupported results
- Digest-pinned typed planning for ten signed APT repositories, including shared HashiCorp setup and dedicated Azure CLI, Google Cloud CLI, and Unity Hub sources, with one de-duplicated index refresh
- Deterministic Ubuntu x64 core and bounded full-catalog slice coverage, including cloud, data, security, game, user-scoped Flathub, machine-scoped Snap/APT, classic confinement, architecture limits, and ordered dependency-aware unsupported diagnostics
- Accepted ADRs for the Go controller, least-privilege broker, provider adapters, and resumable event journal
- Strict dependency-free Go catalog loader and deterministic shadow planner
- Windows provider adapter (`internal/adapter/windows`) with native Winget detection and direct binary execution
- Linux provider adapter (`internal/adapter/linux`) with native APT/dpkg, DNF, Snap, and Flatpak detection plus direct, shell-free typed installation commands
- Verified atomic Ubuntu repository mutation, one APT/DNF refresh, typed native Snap/Flatpak manager installation, Snap activation, and scoped Flathub prerequisites
- Linux-specific configuration handlers with authentication and account state kept manual
- Shared application layer and one Linux `sudo` handoff separating machine operations from user Flatpak/configuration work, with validated streaming events for durable failure/resume state
- One-shot privileged broker (`internal/broker`) with canonical-plan reconstruction, catalog digest matching, real-run elevation enforcement, direct provider execution, installed-package skipping, and redacted event streams
- Strict structured execution journal and flushed atomic state snapshot engine (`internal/journal`) with monotonic sequences and plan-bound fail-closed resumption
- System diagnostic engine (`internal/doctor`) for platform, package manager, workspace directory, and catalog integrity checks
- `cowebs-setup` CLI subcommands (`plan`, `broker`, `status`, `resume`, `doctor`) with `--json` output format support
- Public preview `cowebs` command family for `dev-setup`, including install, plan, status, resume, doctor, update, version, completions, and stable exit contracts
- Cross-platform binary/archive builder, checksum-pinned Unix bootstrap, signed release manifest, SHA-256 list, SPDX SBOM, Winget metadata, and Debian/RPM package definitions
- Tag-bound keyless Sigstore bundles and GitHub artifact provenance with draft and unauthenticated public-download verification
- Disposable Linux failure matrix covering interruption/resume, partial inventory, forced offline failure/recovery, fresh-login PATH, ownership, redaction, cleanup, and repeat-run idempotency
- Exact black-box parity with the PowerShell planner across every profile and selection mode
- The Go binary and schema-v3 catalogs remain excluded from the v6.2 runtime bundle pending an approved cutover
