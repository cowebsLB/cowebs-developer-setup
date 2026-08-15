# Package and Profile Selection

Version 6 separates a dependable workstation core from role essentials and focused use-case packs. This keeps a default install practical while allowing a professional to select the language, cloud, database, security, AI, or game stack actually used by their team.

## Evidence and design principles

The catalog was informed by the [2025 Stack Overflow Developer Survey](https://survey.stackoverflow.co/2025/technology/), the [2025 GitHub Octoverse report](https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/), and the [2025 CNCF Annual Cloud Native Survey](https://www.cncf.io/wp-content/uploads/2026/01/CNCF_Annual_Survey_Report_final.pdf). These sources support broad ecosystem coverage for containers, web and backend languages, Python AI workflows, GitHub collaboration, and cloud-native/Kubernetes tooling. Community discussions were treated as discovery signals, not as enough evidence by themselves; every Windows package also had to exist under an exact current Winget ID.

Defaults follow four rules:

1. Core means broadly useful on a professional Windows workstation.
2. Essentials are directly relevant to the selected role.
3. Recommended packs represent a common, coherent workflow for that role.
4. Heavy, licensed, provider-specific, alternate, or specialized tools remain optional.

## Profile defaults

| Profile | Essentials beyond core | Recommended packs |
|---|---|---|
| Backend | Docker, PostgreSQL, DBeaver, Bruno | Node.js backend |
| Frontend | Node.js, pnpm, Chrome, Firefox, Bruno | Design handoff |
| Android | Android Studio, OpenJDK 21, scrcpy | None |
| DevOps | Docker, Task, yq | WSL/Linux, Kubernetes, IaC, supply-chain security |
| AI/ML | Docker | Modern Python, MLOps/data versioning |
| Cybersecurity | Sysinternals, Nmap, Wireshark | Authorized web testing |
| Game | Shared core | Creative production toolkit |
| Full Stack | Backend plus Frontend | Inherited recommendations |
| Everything | Essentials from every role | Inherited recommendations |

## Pack families

- Backend: Node.js, Python, Java, .NET, Go, Rust, PHP, database clients, and Postman.
- Frontend: Figma handoff, Bun/Deno alternatives, and local tunnels.
- DevOps: WSL/Ubuntu, Kubernetes, OpenTofu/IaC, supply-chain security, Terraform compatibility, and AWS/Azure/GCP CLIs.
- AI/ML: modern Python, Conda alternative, Ollama, DVC, and R/RStudio.
- Cybersecurity: web testing and an explicitly authorized Kali WSL lab.
- Game: creative tools, Unity, Godot, Unreal prerequisites, 2D tools, audio, and Blockbench.

Use `master-setup.bat --list-packs` for authoritative pack keys. Use `--dry-run` to review the complete dependency-expanded plan before installing.

The signed v6.3.0-rc.1 Linux preview consumes these same logical profiles and packs through the deterministic schema-v2 compatibility compiler; it does not maintain forked Linux profile lists. Ubuntu exposes 54 reviewed executable providers and 32 explicit unsupported results, while Fedora exposes 42 and 44 respectively. Always inspect `cowebs plan dev-setup` and the [support matrix](support-matrix.md): an unsupported result is an intentional fail-closed boundary, not permission to substitute an unverified package or installer.

## Important choices

- `ai-python-modern` and `ai-conda` are alternative environment strategies. Use `--essentials-only --pack ai-conda` for Conda.
- Cloud provider CLIs are opt-in because most developers use only one provider.
- Unity and Unreal packs include large vendor-managed components and remain opt-in.
- Security packages are intended only for systems and labs the user is authorized to test.
- The catalog chooses currently discoverable Winget packages; a missing package-manager entry is not replaced with an unverified download script.
