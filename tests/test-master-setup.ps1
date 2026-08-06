$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $projectRoot 'master-setup.bat'
$enginePath = Join-Path $projectRoot 'src\windows\setup.ps1'
$packagesPath = Join-Path $projectRoot 'config\packages.json'
$profilesPath = Join-Path $projectRoot 'config\profiles.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$bootstrap = [IO.File]::ReadAllText($bootstrapPath, [Text.UTF8Encoding]::new($false))
$packages = Get-Content -LiteralPath $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profiles = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-True ($bootstrap -match 'set "VERSION=5\.0\.0"') 'Bootstrap version 5.0.0 is missing.'
Assert-True ($bootstrap -match 'cowebsLB/cowebs-developer-setup') 'Pinned GitHub repository is missing.'
Assert-True ($bootstrap -match 'releases/download/v%VERSION%') 'Pinned release URL is missing.'
Assert-True ($bootstrap -match 'Get-FileHash.*SHA256') 'SHA-256 verification is missing.'
Assert-True ($bootstrap -notmatch '__BUNDLE_SHA256__') 'Release checksum placeholder was not replaced.'
Assert-True ($bootstrap -match 'Banner artwork spells COWEBS\.LB\.') 'Complete COWEBS.LB banner marker is missing.'
Assert-True ($bootstrap -match 'TEMP%\\COWebs\.lb') 'Dedicated temporary root is missing.'
Assert-True ($bootstrap -match 'rmdir /s /q "!SESSION_DIR!"') 'Scoped temporary cleanup is missing.'
Assert-True ($bootstrap -match 'chcp !ORIGINAL_CODE_PAGE!') 'Original console code-page restoration is missing.'
Assert-True (-not [regex]::IsMatch($bootstrap, '(?<!\r)\n')) 'master-setup.bat must use Windows CRLF line endings.'

$packageKeys = @($packages.packages | ForEach-Object { $_.key })
$wingetIds = @($packages.packages | ForEach-Object { $_.platforms.windows.wingetId })
Assert-True ($packages.schemaVersion -eq 1) 'Package schema version must be 1.'
Assert-True ($packageKeys.Count -eq 26) "Expected 26 packages, found $($packageKeys.Count)."
Assert-True (($packageKeys | Sort-Object -Unique).Count -eq $packageKeys.Count) 'Package keys must be unique.'
Assert-True (($wingetIds | Sort-Object -Unique).Count -eq $wingetIds.Count) 'Winget IDs must be unique.'
Assert-True (-not ($wingetIds -contains $null)) 'Every package must have a Windows Winget ID.'

$profileProperties = @($profiles.profiles.PSObject.Properties)
Assert-True ($profiles.schemaVersion -eq 1) 'Profile schema version must be 1.'
Assert-True ($profileProperties.Count -eq 9) "Expected 9 profiles, found $($profileProperties.Count)."
foreach ($profileProperty in $profileProperties) {
    $definition = $profileProperty.Value
    foreach ($packageKey in @($definition.packages)) {
        Assert-True ($packageKeys -contains $packageKey) "Profile '$($profileProperty.Name)' references unknown package '$packageKey'."
    }
    $extendsProperty = $definition.PSObject.Properties['extends']
    if ($extendsProperty) {
        foreach ($parent in @($extendsProperty.Value)) {
            Assert-True ($profiles.profiles.PSObject.Properties.Name -contains $parent) "Profile '$($profileProperty.Name)' extends unknown profile '$parent'."
        }
    }
}

$profileExpectations = [ordered]@{
    backend = 9; frontend = 9; android = 8; devops = 11; ai = 8; cyber = 6; game = 5; fullstack = 13; everything = 26
}
foreach ($profile in $profileExpectations.Keys) {
    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -Profile $profile -DryRun -NoConfig -NoRestart 2>&1
    $exitCode = $LASTEXITCODE
    $joined = $output -join "`n"
    Assert-True ($exitCode -eq 0) "$profile engine dry-run exited with code $exitCode."
    Assert-True ($joined -match "Planned:\s+$($profileExpectations[$profile])") "$profile did not resolve to $($profileExpectations[$profile]) unique packages."
}

$requiredDocumentation = @(
    'README.md', 'CHANGELOG.md', 'docs/index.md', 'docs/architecture.md', 'docs/installation.md',
    'docs/troubleshooting.md', 'docs/features.md', 'docs/roadmap.md', 'docs/API.md', 'docs/Database.md',
    'docs/Security.md', 'docs/Testing.md', 'docs/Deployment.md', 'docs/worklogs/worklog-07-08-2026.md'
)
foreach ($relativePath in $requiredDocumentation) {
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) "Missing documentation file: $relativePath."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'PASS: manifests, profiles, Windows engine dry-runs, bootstrap contract, CRLF, and documentation.'
exit 0
