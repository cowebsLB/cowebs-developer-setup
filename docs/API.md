# CLI and Manifest API

## Windows bootstrap CLI

```text
master-setup.bat [options]
```

- `--profile NAME`: Select `backend`, `frontend`, `android`, `devops`, `ai`, `cyber`, `game`, `fullstack`, or `everything`.
- `--pack NAME`: Add a use-case pack; repeat the option to select several packs.
- `--essentials-only`: Skip recommended packs and use only core tools, role essentials, and explicitly selected packs.
- `--list-packs`: Print all available pack keys and names without installing anything.
- `--dry-run`: Preview without changes; implies no configuration and no restart.
- `--no-config`: Skip optional post-install configuration.
- `--no-restart`: Suppress the restart prompt.
- `--keep-temp`: Retain the verified extracted payload for debugging.
- `--version`: Print the bootstrap version.
- `--help` or `-h`: Print help without downloading the payload.

Exit codes: `0` success, `1` package failure, `2` argument error, `3` missing runtime prerequisite, `4` temporary-directory failure, `5` download/checksum/extraction failure, `6` invalid payload structure, and `7` Administrator approval/elevation failure.

Real installation commands perform one Windows `RunAs` handoff when the current token is not elevated. `--help`, `--version`, `--list-packs`, and `--dry-run` never request elevation. The elevated handoff reconstructs only validated scalar options; selected pack keys are preserved as environment data.

## Package manifest

Schema v2 requires every package to have a unique `key`, display `name`, `tier`, one or more `categories`, `installStrategy`, `license`, and platform mappings. Windows mappings require an exact `wingetId` and can optionally define `wingetOverride`. Reviewed Ubuntu mappings use `support` (`native`, `alternative`, `conditional`, or `unsupported`). Executable mappings require `manager`, `packageId`, `privilege`, `scope`, `architectures`, typed `installOptions`, and conservative `estimate`; Flatpak alone may define a `source`, and `prerequisiteIds` may reference reusable typed Ubuntu prerequisites. Alternatives require `alternativeName`, conditional mappings require `condition`, and unsupported mappings require only `reason`. Optional `configure`, `requires`, `conflictsWith`, and `conditions` values connect shared intent to platform behavior. Referenced dependencies, prerequisites, and conflicts must exist; conflicts are symmetric.

`ubuntuPrerequisites` currently supports `apt-repository`. Each entry declares an ID, architectures, credential-free HTTPS keyring URL, lowercase SHA-256, constrained keyring path, credential-free HTTPS repository base URL, suite, typed components, and constrained `.list` target. The compiler emits these into package catalog v3. A selected provider produces `ensure-repository-key`, `ensure-apt-repository`, and one shared `refresh-package-index` operation; no operation contains a command or shell string.

`windowsEstimatePolicy` defines `default` and `diskHeavy` ranges plus package-keyed `overrides`. Every range contains `downloadMbMin`, `downloadMbMax`, `installMinutesMin`, and `installMinutesMax`. Override keys must reference known packages. These values are planning guidance for a fresh setup; they exclude later SDK, game-engine, model, extension, and update downloads.

## Profile manifest

Schema v2 defines `corePackages`, named `packs`, and named `profiles`. Every profile has a display `name`, a direct `packages` array, `recommendedPacks`, `optionalPacks`, and an optional `extends` array. Cycles and unknown references are invalid. Adapters must resolve dependencies and de-duplicate inherited packages.

The PowerShell engine also accepts `-PackNames`, `-EssentialsOnly`, and `-ListPacks`. `COWEBS_SETUP_PACKS` provides the safe comma-separated bootstrap handoff.

There is no network service API.

## Public COWebs CLI preview contract

The stable cross-platform product entry point is planned as an umbrella `cowebs` CLI with `dev-setup` as the product identifier:

```text
cowebs plan dev-setup [options]
cowebs install dev-setup [options]
cowebs status dev-setup [options]
cowebs resume dev-setup [options]
cowebs doctor dev-setup [options]
cowebs update
```

This command family is implemented in `cmd/cowebs` and published as the signed `v6.3.0-rc.1` preview. `dev-setup` is mandatory for product-scoped commands. Planning and installation accept profile, repeatable pack, essentials-only, dry-run, non-interactive, no-configuration, no-restart, architecture, platform, and JSON options. Exit code `2` denotes command-line usage, `3` denotes complete unsupported-package diagnostics, and `1` denotes other runtime failures. Bash, Zsh, and PowerShell completions and immutable-manifest update checks are covered by tests. The stable Windows runtime remains v6.2.0.

The public preview artifacts are bound to release manifest v1 and source tag `v6.3.0-rc.1`; the manifest records exact platform, architecture, filename, byte size, SHA-256, minimum environment, immutable URL, and tag-specific signature bundle metadata. This API contract does not promote schema v3 to the stable Windows runtime or authorize arbitrary catalog commands.

The terminal CLI calls `internal/application`, the shared typed Go application layer reserved for a future native GUI. A GUI must not parse terminal output or implement a second planner. Native package managers install or update the `cowebs` controller itself; `cowebs install dev-setup` delegates the resolved operations to verified provider adapters and privilege-partitioned brokers.

## Development architecture contracts (source-only in v6.2.0)

The `schema/` directory contains JSON Schema draft 2020-12 contracts for the future cross-platform core:

- package catalog v3;
- profile catalog v3;
- execution plan v1;
- execution event v1;
- release manifest v1.

Schema v3 provider entries declare package manager, exact provider ID, source, privilege, scope, native detection, typed installer options, and provider-specific estimates. Plans and broker messages identify allowlisted operations and intentionally contain no arbitrary command or shell field.

The Linux adapter accepts canonical `ubuntu` and `fedora` plans. Ubuntu permits APT, Snap, and Flatpak; Fedora permits DNF, Snap, and Flatpak. APT, DNF, and Snap are machine-scoped elevated operations. Flatpak requires an explicit remote and either `user`/`user` or `elevated`/`machine` scope. Plans include typed `ensure-manager` operations that install missing Snap/Flatpak managers through fixed native package identities, scoped Flathub setup, one APT or DNF refresh, verified repository-key downloads, and constrained atomic APT source writes. The controller sends machine operations through one `sudo` child, forwards an interrupt to that child, validates and persists child events as a stream, and executes user operations in the initiating process. Catalog discovery checks an explicit path first, then the executable directory, the user XDG data directory, and system data directories. These contracts remain preview APIs until the disposable matrix and public-release verification pass.

Release-manifest v1 records each artifact's immutable URL, size, SHA-256 digest, minimum environment, Sigstore bundle URL, and tag-bound GitHub Actions certificate identity. Signature URL and identity are an all-or-nothing pair. Mutable `github.com/.../blob/main|master` and `raw.githubusercontent.com/.../main|master` URLs are rejected.

Compile the production schema-v2 manifests into deterministic migration artifacts with:

```powershell
./scripts/convert-catalog-v2-to-v3.ps1 -OutputDirectory .tmp/catalog-v3
```

The compiler writes `package-catalog.v3.json` and `profile-catalog.v3.json`. It validates known references, symmetric conflicts, profile inheritance, current Winget mappings, safely representable installer options, and typed Ubuntu provider/prerequisite contracts. All 86 logical packages now have reviewed Ubuntu classifications; 54 emit executable providers and 32 unsupported results intentionally emit no provider. The generated files are development artifacts and are not consumed by the v6.2 runtime.

## Architecture modernization CLI (`cowebs-setup`)

The cross-platform Go binary provides CLI subcommands for planning, execution brokering, session status tracking, state resumption, and system diagnostics:

```powershell
# Plan generation
go run ./cmd/cowebs-setup plan `
  --packages .tmp/catalog-v3/package-catalog.v3.json `
  --profiles .tmp/catalog-v3/profile-catalog.v3.json `
  --profile backend `
  --pack backend-python `
  --platform windows `
  --architecture x64 `
  --json

# Elevated privileged broker execution
go run ./cmd/cowebs-setup broker `
  --plan .tmp/plan.json `
  --packages .tmp/catalog-v3/package-catalog.v3.json `
  --profiles .tmp/catalog-v3/profile-catalog.v3.json `
  --journal .tmp/session.jsonl `
  --state .tmp/state.json `
  --dry-run

# Session status inspection
go run ./cmd/cowebs-setup status `
  --journal .tmp/session.jsonl `
  --state .tmp/state.json `
  --json

# Interrupted session resumption
go run ./cmd/cowebs-setup resume `
  --plan .tmp/plan.json `
  --packages .tmp/catalog-v3/package-catalog.v3.json `
  --profiles .tmp/catalog-v3/profile-catalog.v3.json `
  --journal .tmp/session.jsonl `
  --state .tmp/state.json `
  --dry-run

# System diagnostic checks
go run ./cmd/cowebs-setup doctor `
  --packages .tmp/catalog-v3/package-catalog.v3.json `
  --profiles .tmp/catalog-v3/profile-catalog.v3.json `
  --json
```

`--pack` is repeatable and `--essentials-only` omits inherited recommended packs. Required inputs vary by subcommand. When `broker --journal` omits `--state`, the state path defaults to `<journal>.state.json`; a non-empty journal must be continued through `resume`, never silently appended as a new session. `resume` requires a journal and rejects missing, malformed, or plan/catalog-mismatched state. Invalid catalogs, unknown IDs, dependency cycles, conflicts, non-canonical plans, unknown JSON fields, or missing elevation for a real broker run fail on standard error with a non-zero exit code. If several selected packages lack a provider, planning fails once with `unsupported packages for PLATFORM/ARCH: ID, ...`, retaining deterministic plan order and omitting no unsupported intent.

Plans include the catalog digest, deterministic plan ID, selected packs, aggregate estimate, and ordered typed operations. Detection and installation operations contain only provider identifiers, privilege, scope, source, and tokenized installer options. Repository operations contain typed URLs, digests, constrained paths, suite/components, and architecture; one refresh operation depends on every selected APT repository. Configuration operations contain an allowlisted intent and wait for all planned installs. No operation accepts arbitrary command or shell text.

Before execution, the Windows broker regenerates both valid planner modes from the loaded catalogs and accepts only an exact canonical match. Dry-runs remain unelevated; real runs require an elevated Windows token. Structured events omit raw Winget output. Detection can mark the paired installation as skipped, and resume retains the original session identity while continuing journal sequence numbers.
