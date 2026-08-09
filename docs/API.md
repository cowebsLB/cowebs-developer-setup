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

Schema v2 requires every package to have a unique `key`, display `name`, `tier`, one or more `categories`, `installStrategy`, `license`, and platform mappings. Windows mappings require an exact `wingetId` and can optionally define `wingetOverride`. Optional `configure`, `requires`, `conflictsWith`, and `conditions` values connect shared intent to platform behavior. Referenced dependencies and conflicts must exist; conflicts are symmetric.

`windowsEstimatePolicy` defines `default` and `diskHeavy` ranges plus package-keyed `overrides`. Every range contains `downloadMbMin`, `downloadMbMax`, `installMinutesMin`, and `installMinutesMax`. Override keys must reference known packages. These values are planning guidance for a fresh setup; they exclude later SDK, game-engine, model, extension, and update downloads.

## Profile manifest

Schema v2 defines `corePackages`, named `packs`, and named `profiles`. Every profile has a display `name`, a direct `packages` array, `recommendedPacks`, `optionalPacks`, and an optional `extends` array. Cycles and unknown references are invalid. Adapters must resolve dependencies and de-duplicate inherited packages.

The PowerShell engine also accepts `-PackNames`, `-EssentialsOnly`, and `-ListPacks`. `COWEBS_SETUP_PACKS` provides the safe comma-separated bootstrap handoff.

There is no network service API.

## Unreleased architecture contracts

The `schema/` directory contains JSON Schema draft 2020-12 contracts for the future cross-platform core:

- package catalog v3;
- profile catalog v3;
- execution plan v1;
- execution event v1;
- release manifest v1.

Schema v3 provider entries declare package manager, exact provider ID, source, privilege, scope, native detection, typed installer options, and provider-specific estimates. Plans and broker messages identify allowlisted operations and intentionally contain no arbitrary command or shell field.

Compile the production schema-v2 manifests into deterministic migration artifacts with:

```powershell
./scripts/convert-catalog-v2-to-v3.ps1 -OutputDirectory .tmp/catalog-v3
```

The compiler writes `package-catalog.v3.json` and `profile-catalog.v3.json`. It validates known references, symmetric conflicts, profile inheritance, current Winget mappings, and safely representable installer options. The generated files are development artifacts and are not consumed by v6.1.

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

`--pack` is repeatable and `--essentials-only` omits inherited recommended packs. Required inputs vary by subcommand. When `broker --journal` omits `--state`, the state path defaults to `<journal>.state.json`; a non-empty journal must be continued through `resume`, never silently appended as a new session. `resume` requires a journal and rejects missing, malformed, or plan/catalog-mismatched state. Invalid catalogs, unknown IDs, dependency cycles, conflicts, non-canonical plans, unknown JSON fields, or missing elevation for a real broker run fail on standard error with a non-zero exit code.

Plans include the catalog digest, deterministic plan ID, selected packs, aggregate estimate, and ordered typed operations. Detection and installation operations contain only provider identifiers, privilege, scope, source, and tokenized installer options. Configuration operations contain an allowlisted intent and wait for all planned installs. No operation accepts arbitrary command or shell text.

Before execution, the Windows broker regenerates both valid planner modes from the loaded catalogs and accepts only an exact canonical match. Dry-runs remain unelevated; real runs require an elevated Windows token. Structured events omit raw Winget output. Detection can mark the paired installation as skipped, and resume retains the original session identity while continuing journal sequence numbers.
