# Testing

Run the complete non-installing suite on Windows:

```powershell
./tests/run-tests.ps1
```

The architecture suite requires the Go version declared in `go.mod` (currently 1.26.5). CI installs it with `actions/setup-go@v7`; local development can set `COWEBS_GO_EXE` to an exact toolchain path.

The suite validates:

- JSON Schema draft and stable-ID contracts for package catalog v3, profile catalog v3, execution plans, events, and release manifests;
- deterministic v2-to-v3 compilation with exact preservation of all 86 packages, 34 packs, nine profiles, Windows mappings, dependencies, conflicts, configuration intents, options, and estimates plus complete Ubuntu and Fedora classifications: Ubuntu 54/32 executable/unsupported and Fedora 42/44;
- fail-closed compiler behavior for unknown references, ambiguous quoted legacy overrides, arbitrary Ubuntu fields, stringly typed Ubuntu installer options, credential-bearing prerequisite URLs, and unknown prerequisite references;
- strict Go catalog decoding, reference validation, target validation, dependency ordering, conflict rejection, deterministic plan IDs, configuration barriers, and complete ordered unsupported-package diagnostics;
- independent PowerShell-versus-Go parity for all nine default plans, all nine essentials-only plans, explicit multi-pack composition, exact Winget order, selected packs, estimates, and expected conflict failure;
- canonical-plan regeneration and rejection of digest, provider, option, configuration, and unknown-field tampering before broker execution;
- native process-start failure handling, already-installed package detection and paired-install skipping, and real-run elevation guard wiring;
- Ubuntu/Fedora adapter manager routing, native dpkg/DNF/Snap/Flatpak detection, exact dpkg installed-state checks, typed install arguments, verified atomic APT prerequisites, one APT/DNF refresh, typed manager/Flathub prerequisites, user/machine scope, dry-run isolation, and positional-token rejection;
- the full 11-package Ubuntu x64 core schema-v2 compile and deterministic CLI plan, bounded runtime, productivity/tooling, Kubernetes/IaC/security, and final eighteen-provider cloud/data/security/game plans, ordered dependency-aware unsupported diagnostics, exact typed repository digests, shared prerequisites, one de-duplicated APT refresh, Flathub user scope, reviewed classic Snap options, architecture-specific unsupported diagnostics, and representative planner-to-adapter detection/prerequisite dry-run rendering without installing software;
- durable journal append/flush, state replacement, strict event decoding, monotonic sequence continuation, original-session resume, and plan/catalog mismatch rejection;
- Linux privilege partitioning, allowlisted configuration handlers, explicit manual authentication status, and the shared application-service boundary;
- public `cowebs` product dispatch, exit codes, completions, human/JSON planning, deterministic Fedora planning, and immutable update verification;
- cross-compiled Windows/Linux bundles, executable version identity, release manifest sizes/digests/environment contracts, checksum-pinned Unix bootstrap, SHA-256 list, SPDX SBOM, Winget templates, and Debian/RPM build definitions;
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
- prerelease-default artifact naming and rejection of all published immutable version identities;
- checksum verification, extraction, repeated-pack handoff, final summary, and temporary deletion;
- the complete bootstrap handoff with an intentionally restricted `PSModulePath` and no reliance on `Invoke-WebRequest`, `Get-FileHash`, or `Expand-Archive`;
- required documentation.

GitHub Actions runs the full suite on Windows, Go/static/planner/public-CLI coverage plus a disposable dry-run story on Ubuntu 24.04, and adapter/controller/CLI tests inside Fedora 43. The separate `Disposable Linux installation` workflow requires an exact manual confirmation string, builds and installs the native package, and runs canonical-plan parity, user-owned state, resume, and second-run idempotency checks on either an ephemeral Ubuntu runner or an isolated Fedora 44 LXD system container.

Local release-candidate evidence on 2026-08-15 built and verified the Debian package in an Ubuntu 24.04 container and built, installed, and verified the RPM in a Fedora 44 systemd container. The Fedora core run installed the native manager and first DNF packages, persisted a retryable state through a Snap failure, and reproduced resume correctly. Full Snap completion was not credited because Docker Desktop's kernel lacks SquashFS LZO support; remote LXD/VM evidence remains required.

Real package installations must be tested in Windows Sandbox or a disposable VM before a major public release. Linux validation is guarded by `scripts/validate-linux-disposable.sh`, which refuses to run unless `COWEBS_DISPOSABLE=1` is present and either CI or a virtualization boundary is detected. The harness covers canonical planning, real or dry-run execution, status, and a second idempotency installation. It has not been executed in a real Linux environment in this worktree; unit, contract, and mocked adapter results are not represented as repository availability or real-install evidence.

Before publishing a catalog release, validate each Windows ID with `winget show --id ID --exact --source winget`. The v6.2.0 catalog passed this live check for all 86 IDs on 2026-08-09.
