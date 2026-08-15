$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $projectRoot 'master-setup.bat'
$enginePath = Join-Path $projectRoot 'src\windows\setup.ps1'
$packagesPath = Join-Path $projectRoot 'config\packages.json'
$profilesPath = Join-Path $projectRoot 'config\profiles.json'
$readmePath = Join-Path $projectRoot 'README.md'
$buildScriptPath = Join-Path $projectRoot 'scripts\build-release.ps1'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$bootstrap = [IO.File]::ReadAllText($bootstrapPath, [Text.UTF8Encoding]::new($false))
$engineSource = [IO.File]::ReadAllText($enginePath, [Text.UTF8Encoding]::new($false))
$packages = Get-Content -LiteralPath $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profiles = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
$buildSource = Get-Content -LiteralPath $buildScriptPath -Raw -Encoding UTF8

Assert-True ($bootstrap -match 'set "VERSION=6\.2\.0"') 'Bootstrap version 6.2.0 is missing.'
Assert-True ($bootstrap -match 'cowebsLB/cowebs-developer-setup') 'Pinned GitHub repository is missing.'
Assert-True ($bootstrap -match 'releases/download/v%VERSION%') 'Pinned release URL is missing.'
Assert-True ($bootstrap -match 'Security\.Cryptography\.SHA256') '.NET SHA-256 verification is missing.'
Assert-True ($bootstrap -match 'IO\.Compression\.ZipFile') '.NET ZIP extraction is missing.'
Assert-True ($bootstrap -match 'Net\.WebClient') '.NET release download is missing.'
Assert-True ($bootstrap -notmatch 'Get-FileHash|Expand-Archive|Invoke-WebRequest') 'Bootstrap must not depend on PowerShell utility or archive cmdlets.'
Assert-True ($bootstrap -notmatch '__BUNDLE_SHA256__') 'Release checksum placeholder was not replaced.'
Assert-True ($bootstrap -match 'Banner artwork spells COWEBS\.LB\.') 'Complete COWEBS.LB banner marker is missing.'
Assert-True ($bootstrap -match 'TEMP%\\COWebs\.lb') 'Dedicated temporary root is missing.'
Assert-True ($bootstrap -match 'rmdir /s /q "!SESSION_DIR!"') 'Scoped temporary cleanup is missing.'
Assert-True ($bootstrap -match 'chcp !ORIGINAL_CODE_PAGE!') 'Original console code-page restoration is missing.'
Assert-True ($bootstrap -match '--pack') 'Use-case pack bootstrap option is missing.'
Assert-True ($bootstrap -match '--essentials-only') 'Essentials-only bootstrap option is missing.'
Assert-True ($bootstrap -match '--list-packs') 'Pack listing bootstrap option is missing.'
Assert-True ($bootstrap -match 'COWEBS_SETUP_PACKS') 'Environment-based pack handoff is missing.'
Assert-True ($bootstrap -match 'WindowsPrincipal') 'Administrator-token detection is missing from the bootstrap.'
Assert-True ($bootstrap -match "Verb='RunAs'") 'One-time RunAs elevation is missing from the bootstrap.'
Assert-True ($bootstrap -match 'COWEBS_SETUP_RELAUNCH_PACKS') 'Safe pack preservation across elevation is missing.'
Assert-True ($bootstrap -match '--non-interactive') 'Non-interactive bootstrap option is missing.'
Assert-True ($bootstrap -match 'ENGINE_ARGUMENTS=.*-NonInteractive') 'Non-interactive option is not passed to the Windows engine.'
Assert-True ($bootstrap -match 'RELAUNCH_ARGUMENTS=.*--non-interactive') 'Non-interactive option is not preserved across elevation.'
Assert-True ($bootstrap -match 'if "!DRY_RUN!"=="0"') 'Dry-run elevation bypass is missing.'
Assert-True (-not [regex]::IsMatch($bootstrap, '(?<!\r)\n')) 'master-setup.bat must use Windows CRLF line endings.'
Assert-True ($readme -match 'actions/workflows/validate\.yml/badge\.svg') 'README validation badge is missing.'
Assert-True ($readme -match 'img\.shields\.io/github/v/release') 'README release badge is missing.'
Assert-True ($readme -match 'license-MIT') 'README license badge is missing.'
Assert-True ($readme -match 'platform-Windows') 'README platform badge is missing.'
Assert-True ($readme -match 'manifest-v2') 'README schema badge is missing.'
Assert-True ($buildSource -match "Version = '6\.3\.0-dev'") 'Release builder must default to the next prerelease version.'
Assert-True ($buildSource -match "publishedVersions = @\('6\.0\.0', '6\.1\.0', '6\.2\.0'\)") 'Release builder must protect published immutable versions.'
Assert-True ($engineSource -match "INSTALLING\s*=\s*'Cyan'") 'INSTALLING status must be cyan.'
Assert-True ($engineSource -match "SUCCESS\s*=\s*'Green'") 'SUCCESS status must be green.'
Assert-True ($engineSource -match "SKIPPED\s*=\s*'Yellow'") 'SKIPPED status must be yellow.'
Assert-True ($engineSource -match "FAILED\s*=\s*'Red'") 'FAILED status must be red.'
Assert-True ($engineSource -match 'Add-ConfiguredItem') 'Configured-component tracking is missing.'
Assert-True ($engineSource -match 'Add-ConfigurationFailure') 'Configuration-failure tracking is missing.'
Assert-True ($engineSource -match 'function Test-IsAdministrator') 'Engine administrator check is missing.'
Assert-True ($engineSource -match "exit 7") 'Engine must reject an unelevated real installation.'
Assert-True ($engineSource -match '\[switch\]\$NonInteractive') 'Engine non-interactive switch is missing.'
$detectIndex = $engineSource.IndexOf('& winget list --id $id')
$promptIndex = $engineSource.IndexOf('$skipResponse = Read-Host')
Assert-True ($detectIndex -ge 0 -and $promptIndex -gt $detectIndex) 'Per-package confirmation must occur only after installed-package detection.'

$packageKeys = @($packages.packages | ForEach-Object { $_.key })
$wingetIds = @($packages.packages | ForEach-Object { $_.platforms.windows.wingetId })
Assert-True ($packages.schemaVersion -eq 2) 'Package schema version must be 2.'
Assert-True ($packageKeys.Count -ge 80) "Expected at least 80 professional packages, found $($packageKeys.Count)."
Assert-True (($packageKeys | Sort-Object -Unique).Count -eq $packageKeys.Count) 'Package keys must be unique.'
Assert-True (($wingetIds | Sort-Object -Unique).Count -eq $wingetIds.Count) 'Winget IDs must be unique.'
Assert-True (-not ($wingetIds -contains $null)) 'Every package must have a Windows Winget ID.'
$estimatePolicy = $packages.windowsEstimatePolicy
Assert-True ($null -ne $estimatePolicy) 'Windows estimate policy is missing.'
foreach ($estimateName in @('default', 'diskHeavy')) {
    $estimate = $estimatePolicy.PSObject.Properties[$estimateName].Value
    Assert-True ($estimate.downloadMbMin -gt 0 -and $estimate.downloadMbMax -ge $estimate.downloadMbMin) "Estimate '$estimateName' has an invalid download range."
    Assert-True ($estimate.installMinutesMin -gt 0 -and $estimate.installMinutesMax -ge $estimate.installMinutesMin) "Estimate '$estimateName' has an invalid install-time range."
}
foreach ($overrideProperty in @($estimatePolicy.overrides.PSObject.Properties)) {
    $estimate = $overrideProperty.Value
    Assert-True ($packageKeys -contains $overrideProperty.Name) "Estimate override references unknown package '$($overrideProperty.Name)'."
    Assert-True ($estimate.downloadMbMin -gt 0 -and $estimate.downloadMbMax -ge $estimate.downloadMbMin) "Estimate override '$($overrideProperty.Name)' has an invalid download range."
    Assert-True ($estimate.installMinutesMin -gt 0 -and $estimate.installMinutesMax -ge $estimate.installMinutesMin) "Estimate override '$($overrideProperty.Name)' has an invalid install-time range."
}
foreach ($package in $packages.packages) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($package.name)) "Package '$($package.key)' has no display name."
    Assert-True (-not [string]::IsNullOrWhiteSpace($package.description)) "Package '$($package.key)' has no description."
    Assert-True (@('core', 'recommended', 'optional') -contains $package.tier) "Package '$($package.key)' has invalid tier '$($package.tier)'."
    Assert-True (@($package.categories).Count -gt 0) "Package '$($package.key)' has no category."
    Assert-True (@('winget') -contains $package.installStrategy) "Package '$($package.key)' has unsupported install strategy '$($package.installStrategy)'."
    Assert-True (@('open-source', 'vendor-terms', 'source-available') -contains $package.license) "Package '$($package.key)' has invalid license metadata."
    foreach ($requiredKey in @($package.requires) | Where-Object { $_ }) {
        Assert-True ($packageKeys -contains $requiredKey) "Package '$($package.key)' requires unknown package '$requiredKey'."
    }
    foreach ($conflictKey in @($package.conflictsWith) | Where-Object { $_ }) {
        Assert-True ($packageKeys -contains $conflictKey) "Package '$($package.key)' conflicts with unknown package '$conflictKey'."
        $other = $packages.packages | Where-Object key -eq $conflictKey | Select-Object -First 1
        Assert-True (@($other.conflictsWith) -contains $package.key) "Conflict '$($package.key)' / '$conflictKey' must be symmetric."
    }
}

$profileProperties = @($profiles.profiles.PSObject.Properties)
Assert-True ($profiles.schemaVersion -eq 2) 'Profile schema version must be 2.'
Assert-True ($profileProperties.Count -eq 9) "Expected 9 profiles, found $($profileProperties.Count)."
foreach ($packageKey in @($profiles.corePackages)) {
    Assert-True ($packageKeys -contains $packageKey) "Core catalog references unknown package '$packageKey'."
}
$packProperties = @($profiles.packs.PSObject.Properties)
Assert-True ($packProperties.Count -ge 30) "Expected at least 30 use-case packs, found $($packProperties.Count)."
foreach ($packProperty in $packProperties) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($packProperty.Value.name)) "Pack '$($packProperty.Name)' has no display name."
    Assert-True (@($packProperty.Value.packages).Count -gt 0) "Pack '$($packProperty.Name)' is empty."
    foreach ($packageKey in @($packProperty.Value.packages)) {
        Assert-True ($packageKeys -contains $packageKey) "Pack '$($packProperty.Name)' references unknown package '$packageKey'."
    }
}
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
    foreach ($packKey in @($definition.recommendedPacks) + @($definition.optionalPacks)) {
        Assert-True ($profiles.packs.PSObject.Properties.Name -contains $packKey) "Profile '$($profileProperty.Name)' references unknown pack '$packKey'."
    }
}

$profileExpectations = [ordered]@{
    backend = 17; frontend = 17; android = 14; devops = 29; ai = 16; cyber = 16; game = 17; fullstack = 20; everything = 55
}
$essentialsExpectations = [ordered]@{
    backend = 15; frontend = 16; android = 14; devops = 14; ai = 12; cyber = 14; game = 11; fullstack = 19; everything = 27
}
foreach ($profile in $profileExpectations.Keys) {
    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -Profile $profile -DryRun -NoConfig -NoRestart 2>&1
    $exitCode = $LASTEXITCODE
    $joined = $output -join "`n"
    Assert-True ($exitCode -eq 0) "$profile engine dry-run exited with code $exitCode."
    Assert-True ($joined -match "Planned:\s+$($profileExpectations[$profile])") "$profile did not resolve to $($profileExpectations[$profile]) unique packages."
    Assert-True ($joined -match 'Estimated Download \(fresh setup\):') "$profile did not print a download estimate."
    Assert-True ($joined -match 'Estimated Install Time:') "$profile did not print an install-time estimate."
    Assert-True ($joined -match 'Summary') "$profile did not print the final summary heading."
    Assert-True ($joined -match 'Configured:\s+None \(dry-run\)') "$profile dry-run did not report configuration state."
    Assert-True ($joined -match 'Log:\s+Not created \(dry-run\)') "$profile dry-run did not report log state."
    Assert-True ($joined -match 'Privilege:\s+(Administrator|Standard user \(preview only\))') "$profile dry-run did not report privilege state."

    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -Profile $profile -EssentialsOnly -DryRun -NoConfig -NoRestart 2>&1
    $exitCode = $LASTEXITCODE
    $joined = $output -join "`n"
    Assert-True ($exitCode -eq 0) "$profile essentials-only dry-run exited with code $exitCode."
    Assert-True ($joined -match "Planned:\s+$($essentialsExpectations[$profile])") "$profile essentials-only mode did not resolve to $($essentialsExpectations[$profile]) packages."
}

$output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -Profile backend -PackNames 'backend-python,cloud-aws' -DryRun -NoConfig -NoRestart 2>&1
$joined = $output -join "`n"
Assert-True ($LASTEXITCODE -eq 0) 'Explicit compatible pack selection failed.'
Assert-True ($joined -match 'Packs: backend-node, backend-python, cloud-aws') 'Explicit packs were not merged with the recommended profile pack.'
Assert-True ($joined -match 'Planned:\s+20') 'Explicit pack dependency plan did not resolve to 20 packages.'

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -Profile ai -PackNames 'ai-conda' -DryRun -NoConfig -NoRestart 2>&1
$ErrorActionPreference = $previousErrorAction
$joined = $output -join "`n"
Assert-True ($LASTEXITCODE -ne 0) 'Conflicting Python environment packs should fail.'
Assert-True ($joined -match 'Package\s+conflict') 'Conflicting pack failure did not explain the package conflict.'

$output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -Profile ai -EssentialsOnly -PackNames 'ai-conda' -DryRun -NoConfig -NoRestart 2>&1
Assert-True ($LASTEXITCODE -eq 0) 'Conda pack should work when the recommended uv pack is disabled.'

$output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $enginePath -ListPacks -DryRun -NoConfig -NoRestart 2>&1
$joined = $output -join "`n"
Assert-True ($LASTEXITCODE -eq 0) 'Pack listing failed.'
Assert-True ($joined -match 'backend-python' -and $joined -match 'game-unreal') 'Pack listing is incomplete.'

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
