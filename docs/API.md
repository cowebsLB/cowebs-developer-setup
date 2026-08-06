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
