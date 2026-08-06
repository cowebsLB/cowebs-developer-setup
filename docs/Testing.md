# Testing

Run the complete non-installing suite on Windows:

```powershell
./tests/run-tests.ps1
```

The suite validates:

- JSON syntax and schema versions;
- uniqueness, required metadata, dependency/conflict integrity, and completeness of all 86 package mappings;
- all 34 pack references and all nine profile references and inheritance results;
- direct Windows engine default and essentials-only dry-runs for every profile;
- compatible explicit-pack composition, expected conflict rejection, dependency expansion, and pack listing;
- bootstrap version, release URL, checksum, branding, CRLF, and cleanup contract;
- release ZIP creation;
- checksum verification, extraction, repeated-pack handoff, final summary, and temporary deletion;
- the complete bootstrap handoff with an intentionally restricted `PSModulePath` and no reliance on `Invoke-WebRequest`, `Get-FileHash`, or `Expand-Archive`;
- required documentation.

GitHub Actions runs the same suite on `windows-latest` for pushes and pull requests.

Real package installations must be tested in Windows Sandbox or a disposable VM before a major public release. Dry-run success is not represented as real-install validation.

Before publishing a catalog release, validate each Windows ID with `winget show --id ID --exact --source winget`. The v6.0.0 catalog passed this live check for all 86 IDs on 2026-08-07.
