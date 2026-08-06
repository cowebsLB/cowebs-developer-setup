[CmdletBinding()]
param(
    [ValidateSet('backend', 'frontend', 'android', 'devops', 'ai', 'cyber', 'game', 'fullstack', 'everything')]
    [string]$Profile,
    [string]$PackNames,
    [switch]$EssentialsOnly,
    [switch]$ListPacks,
    [switch]$DryRun,
    [switch]$NoConfig,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packagesPath = Join-Path $projectRoot 'config\packages.json'
$profilesPath = Join-Path $projectRoot 'config\profiles.json'
$logRoot = Join-Path $env:LOCALAPPDATA 'COWebs.lb\Setup\logs'
$script:InstalledCount = 0
$script:SkippedCount = 0
$script:FailedCount = 0
$script:PlannedCount = 0
$script:LogPath = $null

function Write-SetupLog {
    param([string]$Message)
    if ($DryRun -or -not $script:LogPath) { return }
    Add-Content -LiteralPath $script:LogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $answer = Read-Host "$Prompt [Y/N]"
        if ($answer -match '^(?i:y|yes)$') { return $true }
        if ($answer -match '^(?i:n|no)$') { return $false }
        Write-Host 'Please enter Y or N.' -ForegroundColor Yellow
    }
}

function Get-OptionalPropertyValue {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-PackageDefinition {
    param([string]$Key)
    $package = $packageCatalog.packages | Where-Object { $_.key -eq $Key } | Select-Object -First 1
    if (-not $package) { throw "Unknown package key: $Key" }
    return $package
}

function Get-PackDefinition {
    param([string]$Key)
    $property = $profileCatalog.packs.PSObject.Properties[$Key]
    if (-not $property) { throw "Unknown pack: $Key" }
    return $property.Value
}

function Select-SetupProfile {
    $orderedProfiles = @('backend', 'frontend', 'android', 'devops', 'ai', 'cyber', 'game', 'fullstack', 'everything')
    Write-Host 'Select a developer profile:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $orderedProfiles.Count; $index++) {
        $key = $orderedProfiles[$index]
        Write-Host ("  {0}. {1}" -f ($index + 1), $profileCatalog.profiles.$key.name)
    }
    Write-Host '  0. Exit'
    while ($true) {
        $selection = Read-Host 'Choice'
        if ($selection -eq '0') { return $null }
        $number = 0
        if ([int]::TryParse($selection, [ref]$number) -and $number -ge 1 -and $number -le $orderedProfiles.Count) {
            return $orderedProfiles[$number - 1]
        }
        Write-Host 'Choose a number from 0 through 9.' -ForegroundColor Yellow
    }
}

function Get-ProfileMetadata {
    param([string]$ProfileKey)

    $packages = New-Object System.Collections.Generic.List[string]
    $recommendedPacks = New-Object System.Collections.Generic.List[string]
    $optionalPacks = New-Object System.Collections.Generic.List[string]
    $seenPackages = New-Object 'System.Collections.Generic.HashSet[string]'
    $seenRecommended = New-Object 'System.Collections.Generic.HashSet[string]'
    $seenOptional = New-Object 'System.Collections.Generic.HashSet[string]'

    function Add-ProfileMetadata {
        param([string]$Key, [string[]]$Stack)
        if ($Stack -contains $Key) { throw "Profile inheritance cycle detected: $($Stack -join ' -> ') -> $Key" }
        $property = $profileCatalog.profiles.PSObject.Properties[$Key]
        if (-not $property) { throw "Unknown inherited profile: $Key" }
        $definition = $property.Value
        $nextStack = @($Stack) + $Key

        foreach ($parent in @(Get-OptionalPropertyValue $definition 'extends')) {
            if ($parent) { Add-ProfileMetadata -Key $parent -Stack $nextStack }
        }
        foreach ($packageKey in @($definition.packages)) {
            if ($packageKey -and $seenPackages.Add([string]$packageKey)) { $packages.Add([string]$packageKey) }
        }
        foreach ($packKey in @(Get-OptionalPropertyValue $definition 'recommendedPacks')) {
            if ($packKey -and $seenRecommended.Add([string]$packKey)) { $recommendedPacks.Add([string]$packKey) }
        }
        foreach ($packKey in @(Get-OptionalPropertyValue $definition 'optionalPacks')) {
            if ($packKey -and $seenOptional.Add([string]$packKey)) { $optionalPacks.Add([string]$packKey) }
        }
    }

    Add-ProfileMetadata -Key $ProfileKey -Stack @()
    return [pscustomobject]@{
        Packages = $packages.ToArray()
        RecommendedPacks = $recommendedPacks.ToArray()
        OptionalPacks = $optionalPacks.ToArray()
    }
}

function Select-OptionalPacks {
    param([string[]]$AvailablePacks)
    if ($AvailablePacks.Count -eq 0) { return @() }

    Write-Host "`nOptional use-case packs:" -ForegroundColor Cyan
    for ($index = 0; $index -lt $AvailablePacks.Count; $index++) {
        $packKey = $AvailablePacks[$index]
        $pack = Get-PackDefinition $packKey
        Write-Host ("  {0}. {1} ({2})" -f ($index + 1), $pack.name, $packKey)
    }
    Write-Host 'Enter comma-separated numbers or pack names, or press Enter for none.'
    $selection = Read-Host 'Optional packs'
    if (-not $selection) { return @() }

    $selected = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($token in @($selection -split ',')) {
        $value = $token.Trim()
        $number = 0
        if ([int]::TryParse($value, [ref]$number) -and $number -ge 1 -and $number -le $AvailablePacks.Count) {
            $value = $AvailablePacks[$number - 1]
        }
        if ($AvailablePacks -notcontains $value) { throw "Pack '$value' is not available for this profile." }
        if ($seen.Add($value)) { $selected.Add($value) }
    }
    return $selected.ToArray()
}

function Resolve-SetupPlan {
    param([string]$ProfileKey, [string[]]$ExplicitPacks)

    $metadata = Get-ProfileMetadata $ProfileKey
    $selectedPackKeys = New-Object System.Collections.Generic.List[string]
    $seenPacks = New-Object 'System.Collections.Generic.HashSet[string]'
    if (-not $EssentialsOnly) {
        foreach ($packKey in $metadata.RecommendedPacks) {
            if ($seenPacks.Add($packKey)) { $selectedPackKeys.Add($packKey) }
        }
    }
    foreach ($packKey in $ExplicitPacks) {
        [void](Get-PackDefinition $packKey)
        if ($seenPacks.Add($packKey)) { $selectedPackKeys.Add($packKey) }
    }

    $resolved = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    function Add-Package {
        param([string]$Key, [string[]]$Stack)
        if ($Stack -contains $Key) { throw "Package dependency cycle detected: $($Stack -join ' -> ') -> $Key" }
        $package = Get-PackageDefinition $Key
        foreach ($dependency in @(Get-OptionalPropertyValue $package 'requires')) {
            if ($dependency) { Add-Package -Key $dependency -Stack (@($Stack) + $Key) }
        }
        if ($seen.Add($Key)) { $resolved.Add($Key) }
    }

    foreach ($packageKey in $profileCatalog.corePackages) { Add-Package -Key $packageKey -Stack @() }
    foreach ($packageKey in $metadata.Packages) { Add-Package -Key $packageKey -Stack @() }
    foreach ($packKey in $selectedPackKeys) {
        foreach ($packageKey in (Get-PackDefinition $packKey).packages) { Add-Package -Key $packageKey -Stack @() }
    }

    foreach ($packageKey in $resolved) {
        $package = Get-PackageDefinition $packageKey
        foreach ($conflict in @(Get-OptionalPropertyValue $package 'conflictsWith')) {
            if ($conflict -and $seen.Contains([string]$conflict)) {
                throw "Package conflict: '$packageKey' cannot be installed with '$conflict'. Choose compatible packs."
            }
        }
    }

    return [pscustomobject]@{
        PackageKeys = $resolved.ToArray()
        SelectedPacks = $selectedPackKeys.ToArray()
        OptionalPacks = $metadata.OptionalPacks
    }
}

function Install-WindowsPackage {
    param($Package)
    if ($Package.installStrategy -ne 'winget') { throw "Unsupported Windows install strategy '$($Package.installStrategy)' for '$($Package.key)'." }
    $windows = $Package.platforms.windows
    if (-not $windows -or -not $windows.wingetId) { throw "Package '$($Package.key)' has no Windows Winget mapping." }
    $id = [string]$windows.wingetId
    Write-Host "`n--- $($Package.name) ---" -ForegroundColor Cyan

    $conditions = Get-OptionalPropertyValue $Package 'conditions'
    if ($conditions) {
        if (Get-OptionalPropertyValue $conditions 'diskHeavy') { Write-Host '[NOTE] This is a disk-heavy package.' -ForegroundColor DarkYellow }
        $hardware = Get-OptionalPropertyValue $conditions 'hardwareRecommended'
        if ($hardware) { Write-Host "[NOTE] Recommended hardware: $hardware" -ForegroundColor DarkYellow }
        if (Get-OptionalPropertyValue $conditions 'authorizedLabOnly') { Write-Host '[WARNING] Use only in an authorized security lab.' -ForegroundColor Yellow }
    }

    if ($DryRun) {
        Write-Host "[PLANNED] winget install --id `"$id`" --exact --source winget"
        $script:PlannedCount++
        return
    }

    & winget list --id $id --exact --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[SKIPPED] $($Package.name) is already installed." -ForegroundColor DarkGray
        $script:SkippedCount++
        Write-SetupLog "SKIPPED $($Package.name) [$id]."
        return
    }

    Write-Host "[INSTALLING] $($Package.name)" -ForegroundColor Yellow
    Write-SetupLog "INSTALLING $($Package.name) [$id]."
    $arguments = @('install', '--id', $id, '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    $override = Get-OptionalPropertyValue $windows 'wingetOverride'
    if ($override) { $arguments += @('--override', [string]$override) }
    & winget @arguments
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[SUCCESS] $($Package.name)" -ForegroundColor Green
        $script:InstalledCount++
        Write-SetupLog "SUCCESS $($Package.name) [$id]."
    } else {
        Write-Host "[FAILED] $($Package.name) - Winget exit code $LASTEXITCODE." -ForegroundColor Red
        $script:FailedCount++
        Write-SetupLog "FAILED $($Package.name) [$id] exit=$LASTEXITCODE."
    }
}

function Refresh-ProcessPath {
    if ($DryRun) { return }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath;$env:Path"
    Write-SetupLog 'Refreshed process PATH from machine and user environment settings.'
}

function Invoke-Configuration {
    param([string]$ConfigurationKey)
    switch ($ConfigurationKey) {
        'git' {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Warning 'Git is unavailable; skipping configuration.'; return }
            if (-not (Read-YesNo 'Configure Git defaults and identity?')) { return }
            $name = Read-Host 'Git name'; $email = Read-Host 'Git email'
            if (-not $name -or -not $email) { Write-Warning 'Git name and email are required; skipping.'; return }
            & git config --global user.name $name; & git config --global user.email $email
            & git config --global init.defaultBranch main; & git config --global pull.rebase false; & git config --global core.autocrlf true
            Write-SetupLog 'Configured Git identity and defaults.'
        }
        'git-lfs' {
            if (Get-Command git -ErrorAction SilentlyContinue) { & git lfs install; Write-SetupLog 'Configured Git LFS.' }
        }
        'github' {
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Warning 'GitHub CLI is unavailable; skipping login.'; return }
            if (Read-YesNo 'Log in to GitHub CLI?') { & gh auth login; Write-SetupLog 'GitHub CLI login command completed.' }
        }
        'vscode' {
            if (-not (Get-Command code -ErrorAction SilentlyContinue)) { Write-Warning 'VS Code CLI is unavailable; skipping extensions.'; return }
            if (-not (Read-YesNo 'Install the COWebs.lb recommended VS Code extensions?')) { return }
            @('GitHub.copilot', 'GitHub.copilot-chat', 'eamodio.gitlens', 'ms-python.python', 'dbaeumer.vscode-eslint', 'esbenp.prettier-vscode') | ForEach-Object { & code --install-extension $_ }
            Write-SetupLog 'Requested recommended VS Code extensions.'
        }
        'node' {
            if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Write-Warning 'npm is unavailable; skipping Node configuration.'; return }
            if (Read-YesNo 'Update npm and enable Corepack?') { & npm install --global npm; & corepack enable; Write-SetupLog 'Node.js configuration commands completed.' }
        }
        'python' {
            if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Write-Warning 'Python is unavailable; skipping packages.'; return }
            if (Read-YesNo 'Upgrade pip and install common Python quality tools?') { & python -m pip install --upgrade pip; & python -m pip install black flake8 pytest requests; Write-SetupLog 'Python package commands completed.' }
        }
        'uv' {
            if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { Write-Warning 'uv is unavailable; skipping Python installation.'; return }
            if (Read-YesNo 'Install managed Python 3.14 with uv?') { & uv python install 3.14; Write-SetupLog 'uv Python installation command completed.' }
        }
        'docker' {
            if (-not (Read-YesNo 'Launch Docker Desktop?')) { return }
            $dockerPath = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
            if (Test-Path -LiteralPath $dockerPath) { Start-Process -FilePath $dockerPath; Write-SetupLog 'Docker Desktop launch requested.' } else { Write-Warning 'Docker Desktop executable was not found at the default location.' }
        }
        'aws' {
            if ((Get-Command aws -ErrorAction SilentlyContinue) -and (Read-YesNo 'Run aws configure?')) { & aws configure; Write-SetupLog 'AWS configuration completed; credentials were not logged.' }
        }
        'azure' {
            if ((Get-Command az -ErrorAction SilentlyContinue) -and (Read-YesNo 'Log in to Azure CLI?')) { & az login; Write-SetupLog 'Azure login completed; credentials were not logged.' }
        }
    }
}

$packageCatalog = Get-Content -LiteralPath $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profileCatalog = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($packageCatalog.schemaVersion -ne 2 -or $profileCatalog.schemaVersion -ne 2) { throw 'Manifest schema version 2 is required.' }

if ($ListPacks) {
    Write-Host 'Available use-case packs:' -ForegroundColor Cyan
    foreach ($property in $profileCatalog.packs.PSObject.Properties) {
        Write-Host ("  {0,-26} {1}" -f $property.Name, $property.Value.name)
    }
    exit 0
}

$profileWasProvided = [bool]$Profile
if (-not $Profile) {
    $Profile = Select-SetupProfile
    if (-not $Profile) { exit 0 }
}

$explicitPacks = New-Object System.Collections.Generic.List[string]
$packInput = @($PackNames, $env:COWEBS_SETUP_PACKS) | Where-Object { $_ }
foreach ($inputValue in $packInput) {
    foreach ($packKey in @($inputValue -split ',')) {
        $trimmed = $packKey.Trim()
        if ($trimmed -and -not $explicitPacks.Contains($trimmed)) { $explicitPacks.Add($trimmed) }
    }
}

if (-not $profileWasProvided -and -not $EssentialsOnly) {
    $metadata = Get-ProfileMetadata $Profile
    foreach ($packKey in (Select-OptionalPacks $metadata.OptionalPacks)) {
        if (-not $explicitPacks.Contains($packKey)) { $explicitPacks.Add($packKey) }
    }
}

$plan = Resolve-SetupPlan -ProfileKey $Profile -ExplicitPacks $explicitPacks.ToArray()
$profileDefinition = $profileCatalog.profiles.PSObject.Properties[$Profile].Value

if (-not $DryRun) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Error 'Winget is required. Install Microsoft App Installer and try again.'; exit 3 }
    $authorizedLabPackages = @($plan.PackageKeys | ForEach-Object { Get-PackageDefinition $_ } | Where-Object { $conditions = Get-OptionalPropertyValue $_ 'conditions'; $conditions -and (Get-OptionalPropertyValue $conditions 'authorizedLabOnly') })
    if ($authorizedLabPackages.Count -gt 0 -and -not (Read-YesNo 'Confirm these tools will be used only in an authorized security lab?')) { Write-Error 'Authorized lab confirmation was declined.'; exit 4 }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $script:LogPath = Join-Path $logRoot ("setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-SetupLog "Started Windows profile $Profile with $($plan.PackageKeys.Count) unique packages and packs: $($plan.SelectedPacks -join ', ')."
}

Write-Host "`nCOWebs.lb Windows Setup - $($profileDefinition.name)" -ForegroundColor Cyan
Write-Host "$($plan.PackageKeys.Count) unique packages selected."
if ($plan.SelectedPacks.Count -gt 0) { Write-Host "Packs: $($plan.SelectedPacks -join ', ')" }
if ($EssentialsOnly) { Write-Host 'Mode: essentials only' }
foreach ($packageKey in $plan.PackageKeys) { Install-WindowsPackage -Package (Get-PackageDefinition $packageKey) }

Refresh-ProcessPath
if (-not $DryRun -and -not $NoConfig -and (Read-YesNo 'Run optional post-install configuration?')) {
    $configurationKeys = New-Object System.Collections.Generic.List[string]
    $seenConfigurations = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($packageKey in $plan.PackageKeys) {
        $configure = Get-OptionalPropertyValue (Get-PackageDefinition $packageKey) 'configure'
        if ($configure -and $seenConfigurations.Add([string]$configure)) { $configurationKeys.Add([string]$configure) }
    }
    foreach ($configurationKey in $configurationKeys) { Invoke-Configuration $configurationKey }
}

if ($DryRun) {
    Write-Host "`n[PLANNED] Ensure Projects, Workspace, and Scripts exist under the user profile."
} else {
    @('Projects', 'Workspace', 'Scripts') | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $_) -Force | Out-Null }
    Write-SetupLog 'Ensured user workspace folders exist.'
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Profile:   $($profileDefinition.name)"
if ($DryRun) { Write-Host "Planned:   $($script:PlannedCount)" } else {
    Write-Host "Installed: $($script:InstalledCount)"; Write-Host "Skipped:   $($script:SkippedCount)"; Write-Host "Failed:    $($script:FailedCount)"; Write-Host "Log:       $($script:LogPath)"
    Write-SetupLog "Finished: installed=$($script:InstalledCount), skipped=$($script:SkippedCount), failed=$($script:FailedCount)."
}
Write-Host '============================================================' -ForegroundColor Cyan

if (-not $DryRun -and -not $NoRestart -and (Read-YesNo 'Restart Windows now?')) { Restart-Computer }
if ($script:FailedCount -gt 0) { exit 1 }
exit 0
