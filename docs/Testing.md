# Testing

Run the complete non-installing suite on Windows:

```powershell
./tests/run-tests.ps1
```

The suite validates:

- JSON syntax and schema versions;
- uniqueness and completeness of all 26 package mappings;
- all nine profile references and inheritance results;
- direct Windows engine dry-runs for every profile;
- bootstrap version, release URL, checksum, branding, CRLF, and cleanup contract;
- release ZIP creation;
- checksum verification, extraction, engine handoff, final summary, and temporary deletion;
- required documentation.

GitHub Actions runs the same suite on `windows-latest` for pushes and pull requests.

Real package installations must be tested in Windows Sandbox or a disposable VM before a major public release. Dry-run success is not represented as real-install validation.
