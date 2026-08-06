[CmdletBinding()]
param(
    [ValidateSet('backend', 'frontend', 'android', 'devops', 'ai', 'cyber', 'game', 'fullstack', 'everything')]
    [string]$Profile,
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

    if ($DryRun -or -not $script:LogPath) {
        return
    }

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

function Select-SetupProfile {
    $orderedProfiles = @('backend', 'frontend', 'android', 'devops', 'ai', 'cyber', 'game', 'fullstack', 'everything')
    Write-Host 'Select a developer profile:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $orderedProfiles.Count; $index++) {
        $key = $orderedProfiles[$index]
        $displayName = $profiles.profiles.$key.name
        Write-Host ("  {0}. {1}" -f ($index + 1), $displayName)
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

function Resolve-ProfilePlan {
    param([string]$ProfileKey)

    $resolved = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    function Add-ProfilePackages {
        param([string]$Key, [string[]]$Stack)

        if ($Stack -contains $Key) {
            throw "Profile inheritance cycle detected: $($Stack -join ' -> ') -> $Key"
        }

        $property = $profiles.profiles.PSObject.Properties[$Key]
        if (-not $property) {
            throw "Unknown inherited profile: $Key"
        }

        $definition = $property.Value
        $nextStack = @($Stack) + $Key
        $extendsProperty = $definition.PSObject.Properties['extends']
        if ($extendsProperty) {
            foreach ($parent in @($extendsProperty.Value)) {
                if ($parent) { Add-ProfilePackages -Key $parent -Stack $nextStack }
            }
        }
        foreach ($packageKey in @($definition.packages)) {
            if ($packageKey -and $seen.Add([string]$packageKey)) {
                $resolved.Add([string]$packageKey)
            }
        }
    }

    Add-ProfilePackages -Key $ProfileKey -Stack @()
    return $resolved.ToArray()
}

function Get-PackageDefinition {
    param([string]$Key)

    $package = $packages.packages | Where-Object { $_.key -eq $Key } | Select-Object -First 1
    if (-not $package) {
        throw "Profile references unknown package key: $Key"
    }
    if (-not $package.platforms.windows.wingetId) {
        throw "Package '$Key' has no Windows Winget mapping."
    }
    return $package
}

function Install-WindowsPackage {
    param($Package)

    $id = [string]$Package.platforms.windows.wingetId
    Write-Host "`n--- $($Package.name) ---" -ForegroundColor Cyan

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
    & winget install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
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
            $name = Read-Host 'Git name'
            $email = Read-Host 'Git email'
            if (-not $name -or -not $email) { Write-Warning 'Git name and email are required; skipping.'; return }
            & git config --global user.name $name
            & git config --global user.email $email
            & git config --global init.defaultBranch main
            & git config --global pull.rebase false
            & git config --global core.autocrlf true
            Write-SetupLog 'Configured Git identity and defaults.'
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
            if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Write-Warning 'npm is unavailable; skipping global tools.'; return }
            if (Read-YesNo 'Install global Node.js developer tools?') { & npm install --global npm pnpm yarn typescript eslint prettier; Write-SetupLog 'Global Node.js tool command completed.' }
        }
        'python' {
            if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Write-Warning 'Python is unavailable; skipping packages.'; return }
            if (Read-YesNo 'Upgrade pip and install common Python packages?') { & python -m pip install --upgrade pip; & python -m pip install black flake8 pytest requests numpy pandas; Write-SetupLog 'Python package commands completed.' }
        }
        'docker' {
            if (-not (Read-YesNo 'Launch Docker Desktop?')) { return }
            $dockerPath = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
            if (Test-Path -LiteralPath $dockerPath) { Start-Process -FilePath $dockerPath; Write-SetupLog 'Docker Desktop launch requested.' } else { Write-Warning 'Docker Desktop executable was not found at the default location.' }
        }
        'aws' {
            if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Write-Warning 'AWS CLI is unavailable; skipping configuration.'; return }
            if (Read-YesNo 'Run aws configure?') { & aws configure; Write-SetupLog 'AWS configuration command completed; credentials were not logged.' }
        }
        'azure' {
            if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Warning 'Azure CLI is unavailable; skipping login.'; return }
            if (Read-YesNo 'Log in to Azure CLI?') { & az login; Write-SetupLog 'Azure login command completed; credentials were not logged.' }
        }
    }
}

$packages = Get-Content -LiteralPath $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profiles = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $Profile) {
    $Profile = Select-SetupProfile
    if (-not $Profile) { exit 0 }
}

$profileDefinition = $profiles.profiles.PSObject.Properties[$Profile].Value
$plan = Resolve-ProfilePlan -ProfileKey $Profile

if (-not $DryRun) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error 'Winget is required. Install Microsoft App Installer and try again.'
        exit 3
    }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $script:LogPath = Join-Path $logRoot ("setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-SetupLog "Started Windows profile $Profile with $($plan.Count) unique packages."
}

Write-Host "`nCOWebs.lb Windows Setup - $($profileDefinition.name)" -ForegroundColor Cyan
Write-Host "$($plan.Count) unique packages selected."
foreach ($packageKey in $plan) {
    Install-WindowsPackage -Package (Get-PackageDefinition -Key $packageKey)
}

Refresh-ProcessPath

if (-not $DryRun -and -not $NoConfig -and (Read-YesNo 'Run optional post-install configuration?')) {
    $configurationKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($packageKey in $plan) {
        $package = Get-PackageDefinition -Key $packageKey
        $configureProperty = $package.PSObject.Properties['configure']
        if ($configureProperty -and $configureProperty.Value) { [void]$configurationKeys.Add([string]$configureProperty.Value) }
    }
    foreach ($configurationKey in $configurationKeys) { Invoke-Configuration -ConfigurationKey $configurationKey }
}

if ($DryRun) {
    Write-Host "`n[PLANNED] Ensure Projects, Workspace, and Scripts exist under the user profile."
} else {
    @('Projects', 'Workspace', 'Scripts') | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE $_) -Force | Out-Null }
    Write-SetupLog 'Ensured user workspace folders exist.'
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "Profile:   $($profileDefinition.name)"
if ($DryRun) {
    Write-Host "Planned:   $($script:PlannedCount)"
} else {
    Write-Host "Installed: $($script:InstalledCount)"
    Write-Host "Skipped:   $($script:SkippedCount)"
    Write-Host "Failed:    $($script:FailedCount)"
    Write-Host "Log:       $($script:LogPath)"
    Write-SetupLog "Finished: installed=$($script:InstalledCount), skipped=$($script:SkippedCount), failed=$($script:FailedCount)."
}
Write-Host '============================================================' -ForegroundColor Cyan

if (-not $DryRun -and -not $NoRestart -and (Read-YesNo 'Restart Windows now?')) {
    Restart-Computer
}

if ($script:FailedCount -gt 0) { exit 1 }
exit 0
