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

GitHub Actions runs the full suite on Windows, Go/static/planner/public-CLI coverage plus a disposable dry-run story on Ubuntu 24.04, and adapter/controller/CLI tests inside Fedora 43. The separate `Disposable Linux installation` workflow requires an exact manual confirmation string, builds and installs the native package, and runs the `matrix` harness on either an ephemeral Ubuntu runner or an isolated Fedora 44 LXD virtual machine. A foreground Python supervisor starts the tested CLI in a new session, observes a persisted started event, sends process-group SIGINT, and bounds termination without inheriting Bash background-job signal dispositions. The matrix then proves bounded native-manager quiescence/retry/resume, partial-host skipping, forced network failure and recovery, fresh-login PATH, canonical-plan parity, user-owned JSON-only/redacted state, cleanup, and second-run idempotency. The forced-source case removes the planned native 7zip package, clears the disposable APT/DNF package cache, and runs its reinstall inside a network namespace; Snap is not used for this assertion because the host `snapd` service owns downloads outside the client namespace. Provider-state assertions use the same manager identity as planning and detection. A complete state may retain `planned` detection results whose paired install operation succeeded; it must contain one final status for every canonical operation and no `started` or `failed` status.

Local release-candidate evidence on 2026-08-15 built and verified the Debian package in an Ubuntu 24.04 container and built, installed, and verified the RPM in a Fedora 44 systemd container. The Fedora core run installed the native manager and first DNF packages, persisted a retryable state through a Snap failure, and reproduced resume correctly. Full Snap completion was not credited because Docker Desktop's kernel lacks SquashFS LZO support; remote LXD/VM evidence remains required.

Guarded GitHub Actions run `31851004282` passed the complete Ubuntu native-package, real-install, canonical-plan, ownership, resume, and idempotency story. The first Fedora dispatch `31851006495` stopped before package provisioning because cloud-init returned its recoverable-error container status; the workflow now uses bounded DNF readiness instead, and that infrastructure-only attempt is not counted as product evidence.

Fedora retry `31851169165` reached the native RPM installation and validation-user setup, then the disposable guard correctly refused execution because `sudo` had removed the two LXD-level safety variables. The workflow now assigns `CI=true` and `COWEBS_DISPOSABLE=1` after the user transition so the guarded script receives them without weakening its host-protection checks.

Run `31851423627` attempt 1 encountered transient Fedora mirror DNS failure before provisioning. Its unchanged attempt 2 passed LXD, RPM, user setup, doctor, and disposable authorization, then reproduced the VS Code Snap failure even though the ephemeral unprivileged instance already enabled `security.nesting=true`. The workflow now emits Snap changes plus the last 100 `snapd` journal lines only after failure so the remaining confinement or kernel boundary can be diagnosed without making the container privileged on assumption.

Diagnostic run `31851784488` proved that Snap downloaded Code but failed when systemd started the generated SquashFS mount unit inside the shared-kernel LXD container. That environment is therefore not credited as Fedora completion. The guarded Fedora job now launches a full LXD VM with its own Fedora kernel; nested virtualization availability on standard GitHub-hosted runners remains an external CI capability to prove in the next dispatch.

VM run `31851986797` successfully downloaded, unpacked, and started the Fedora virtual machine, proving the hosted runner exposed the required virtualization. Provisioning stopped because the workflow invoked `lxc exec` once before the guest agent was ready. Readiness now retries from the LXD host for up to two minutes, so an unavailable guest agent is polled rather than preventing the intended in-guest DNF check from starting.

Corrected Fedora VM run `31852156303` passed in 4 minutes 29 seconds: VM/RPM provisioning, root-owned installed files, unprivileged doctor and real setup, DNF and Snap completion on the Fedora guest kernel, byte-equal canonical plan output, initiating-user journal ownership, completed-state resume, a second idempotent installation, and unconditional VM deletion. Together with Ubuntu run `31851004282`, the guarded core fresh/resume/idempotency story is complete on both Linux targets. The expanded matrix is implemented but is not credited until new Ubuntu and Fedora workflow runs pass.

Real package installations must be tested in Windows Sandbox or a disposable VM before a major public release. Linux validation is guarded by `scripts/validate-linux-disposable.sh`, which refuses to run unless `COWEBS_DISPOSABLE=1` is present and either CI or a virtualization boundary is detected. Unit, contract, and mocked adapter results are never represented as repository availability or real-install evidence.

`tests/test-signed-release.ps1` covers native-package inclusion, eight-record manifest completeness, signature-pair rules, checksum coverage, and SBOM coverage. The release workflow is parsed as YAML and linted with actionlint before tagging. After publication it independently verifies every public byte and Sigstore bundle, the GitHub attestation, the downloaded bootstrap, binary version output, and default XDG catalog discovery.

Final v6.3.0-rc.1 evidence: local `tests/run-tests.ps1` passed in 242.8 seconds; normal CI `31856222715` passed Windows, Ubuntu, and Fedora; Ubuntu disposable matrix `31856228013` passed; Fedora 44 VM matrix `31856229843` passed; and release workflow `31856640404` passed build, signature, provenance, draft, public-download, bootstrap, version, and catalog-discovery verification.

Before publishing a catalog release, validate each Windows ID with `winget show --id ID --exact --source winget`. The v6.2.0 catalog passed this live check for all 86 IDs on 2026-08-09.
