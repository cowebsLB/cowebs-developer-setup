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
| Ubuntu | Full x64 core plus bounded runtime, productivity/tooling, and Kubernetes/IaC/security planning (source-only; not installable) | Fifty-eight classifications: thirty-six executable providers and twenty-two explicit unsupported results |
| Fedora | Adapter foundation (source-only) | DNF, Snap, or Flatpak where appropriate |

## Development architecture modernization (source-only in v6.2.0)

- Provider-aware package and profile schemas for the future cross-platform core
- Typed execution-plan, event, and release-manifest contracts
- Deterministic schema-v2 to schema-v3 compatibility compiler
- Typed Ubuntu compatibility input for native, alternative, conditional, and unsupported classifications
- Fifty-eight reviewed Ubuntu classifications covering the core, runtime, productivity/tooling, and Kubernetes/IaC/security slices, with thirty-six executable providers and twenty-two explicit unsupported results
- Digest-pinned typed planning for seven signed APT repositories, including shared HashiCorp setup for Terraform, Vault, and Packer, with one de-duplicated index refresh
- Full deterministic Ubuntu x64 core coverage plus bounded runtime, productivity/tooling, and Kubernetes/IaC/security planning, including user-scoped Flathub, machine-scoped Snap/APT, classic confinement, and ordered dependency-aware unsupported diagnostics
- Accepted ADRs for the Go controller, least-privilege broker, provider adapters, and resumable event journal
- Strict dependency-free Go catalog loader and deterministic shadow planner
- Windows provider adapter (`internal/adapter/windows`) with native Winget detection and direct binary execution
- Linux provider adapter (`internal/adapter/linux`) with native APT/dpkg, DNF, Snap, and Flatpak detection plus direct, shell-free typed installation commands
- One-shot privileged broker (`internal/broker`) with canonical-plan reconstruction, catalog digest matching, real-run elevation enforcement, direct provider execution, installed-package skipping, and redacted event streams
- Strict structured execution journal and flushed atomic state snapshot engine (`internal/journal`) with monotonic sequences and plan-bound fail-closed resumption
- System diagnostic engine (`internal/doctor`) for platform, package manager, workspace directory, and catalog integrity checks
- `cowebs-setup` CLI subcommands (`plan`, `broker`, `status`, `resume`, `doctor`) with `--json` output format support
- Exact black-box parity with the PowerShell planner across every profile and selection mode
- The Go binary and schema-v3 catalogs remain excluded from the v6.2 runtime bundle pending an approved cutover
