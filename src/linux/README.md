# Linux platform

The source-only Go foundation now includes a typed Ubuntu/Fedora provider adapter in `internal/adapter/linux`. It directly invokes `apt-get`, `dnf`, `snap`, or `flatpak` without a command shell, uses native manager inventory queries, and validates each operation's platform, privilege, scope, source, package identifier, and typed installer options before execution.

This is not yet a runnable public Linux setup. The production schema-v2 catalog remains Windows-authoritative and does not contain reviewed Linux provider mappings, the privileged broker currently executes Windows plans only, and the v6.2 runtime ZIP contains only the Windows PowerShell engine and shared schema-v2 catalogs. The next Linux milestones are:

1. add reviewed Ubuntu and Fedora provider mappings through the deterministic catalog compiler;
2. add explicit unsupported-package reporting for incomplete profiles;
3. connect Linux plans to a least-privilege controller/broker path;
4. add a checksum-pinned Unix bootstrap and per-distribution disposable-VM tests.

The argument contracts follow the upstream [APT/dpkg manuals](https://manpages.ubuntu.com/), [DNF command reference](https://dnf.readthedocs.io/en/stable/command_ref.html), [Snap documentation](https://snapcraft.io/docs/tutorials/get-started/), and [Flatpak command reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html). Provider IDs and remotes still require package-by-package review before they enter the deterministic catalog.
