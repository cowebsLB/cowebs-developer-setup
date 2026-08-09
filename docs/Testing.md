# Testing

Run the complete non-installing suite on Windows:

```powershell
./tests/run-tests.ps1
```

The architecture suite requires the Go version declared in `go.mod` (currently 1.26.5). CI installs it with `actions/setup-go@v7`; local development can set `COWEBS_GO_EXE` to an exact toolchain path.

The suite validates:

- JSON Schema draft and stable-ID contracts for package catalog v3, profile catalog v3, execution plans, events, and release manifests;
- deterministic v2-to-v3 compilation with exact preservation of all 86 packages, 34 packs, nine profiles, mappings, dependencies, conflicts, configuration intents, options, and estimates;
- fail-closed compiler behavior for unknown references and ambiguous quoted legacy overrides;
- strict Go catalog decoding, reference validation, target validation, dependency ordering, conflict rejection, deterministic plan IDs, and configuration barriers;
- independent PowerShell-versus-Go parity for all nine default plans, all nine essentials-only plans, explicit multi-pack composition, exact Winget order, selected packs, estimates, and expected conflict failure;
- canonical-plan regeneration and rejection of digest, provider, option, configuration, and unknown-field tampering before broker execution;
- native process-start failure handling, already-installed package detection and paired-install skipping, and real-run elevation guard wiring;
- durable journal append/flush, state replacement, strict event decoding, monotonic sequence continuation, original-session resume, and plan/catalog mismatch rejection;
- byte-identical Go JSON output for identical catalogs and inputs;
- JSON syntax and schema versions;
- uniqueness, required metadata, dependency/conflict integrity, and completeness of all 86 package mappings;
- all 34 pack references and all nine profile references and inheritance results;
- direct Windows engine default and essentials-only dry-runs for every profile;
- compatible explicit-pack composition, expected conflict rejection, dependency expansion, and pack listing;
- estimate-policy ranges and override references, estimate rendering for every profile, status-color contracts, and final-summary fields;
- bootstrap and engine Administrator-token checks, one-time `RunAs` handoff, privilege-state rendering, safe pack preservation, and dry-run elevation bypass;
- per-package confirmation ordering and `--non-interactive` propagation through bootstrap, elevation handoff, and engine invocation;
- bootstrap version, release URL, checksum, branding, CRLF, and cleanup contract;
- release ZIP creation;
- prerelease-default artifact naming and rejection of already-published immutable version identities;
- checksum verification, extraction, repeated-pack handoff, final summary, and temporary deletion;
- the complete bootstrap handoff with an intentionally restricted `PSModulePath` and no reliance on `Invoke-WebRequest`, `Get-FileHash`, or `Expand-Archive`;
- required documentation.

GitHub Actions runs the same suite on `windows-latest` for pushes and pull requests using Node 24-compatible checkout and Go setup actions.

Real package installations must be tested in Windows Sandbox or a disposable VM before a major public release. Dry-run success is not represented as real-install validation.

Before publishing a catalog release, validate each Windows ID with `winget show --id ID --exact --source winget`. The catalog passed this live check for all 86 IDs on 2026-08-07.
