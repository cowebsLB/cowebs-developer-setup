# Security

## Trust boundary

The BAT executes only a release payload whose SHA-256 matches the value embedded in that BAT version. It never clones or executes the mutable default branch.

## Temporary cleanup

Each session creates `%TEMP%\COWebs.lb\setup-<random>-<random>`. Cleanup references the exact constructed session path, never `%TEMP%`, a user profile, repository root, wildcard, or unresolved broad path. `--keep-temp` is an explicit debugging override.

## Credentials and logs

GitHub, AWS, and Azure authentication remain interactive. Logs record outcomes but never passwords, access tokens, cloud keys, authentication cookies, or raw authentication output. Logs are copied nowhere because they are created directly in their persistent location outside the temporary payload.

## Package installation

Windows packages use exact identifiers and the explicit Winget community source. Elevation is delegated to Winget/package manifests rather than requiring the entire bootstrap to run as Administrator.

## Remaining limitations

- SHA-256 protects payload integrity relative to the downloaded BAT; code signing is planned for stronger publisher identity.
- Package manifests and upstream installers remain external dependencies.
- Users should obtain the BAT only from the official GitHub release or COWebs.lb site.
