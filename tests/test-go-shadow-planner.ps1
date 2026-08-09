$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1'
$setupPath = Join-Path $projectRoot 'src\windows\setup.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-go-shadow-{0}" -f [guid]::NewGuid().ToString('N'))
$powerShellExe = (Get-Process -Id $PID).Path

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Resolve-GoExecutable {
    if ($env:COWEBS_GO_EXE) {
        if (-not (Test-Path -LiteralPath $env:COWEBS_GO_EXE)) { throw "COWEBS_GO_EXE does not exist: $env:COWEBS_GO_EXE" }
        return $env:COWEBS_GO_EXE
    }
    $command = Get-Command go -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $workspaceTool = Join-Path $projectRoot '.tmp\go-toolchain\go\bin\go.exe'
    if (Test-Path -LiteralPath $workspaceTool) { return $workspaceTool }
    throw 'Go is required for the shadow planner tests. Install the go.mod version or set COWEBS_GO_EXE.'
}

function Invoke-LegacyPlan {
    param([string]$Profile, [string[]]$Packs, [bool]$EssentialsOnly)
    $arguments = @('-NoLogo', '-NoProfile', '-File', $setupPath, '-Profile', $Profile, '-DryRun', '-NoConfig', '-NoRestart')
    if ($Packs.Count -gt 0) { $arguments += @('-PackNames', ($Packs -join ',')) }
    if ($EssentialsOnly) { $arguments += '-EssentialsOnly' }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $powerShellExe @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Invoke-ShadowPlan {
    param([string]$Executable, [string]$PackagesPath, [string]$ProfilesPath, [string]$Profile, [string[]]$Packs, [bool]$EssentialsOnly)
    $arguments = @('plan', '--packages', $PackagesPath, '--profiles', $ProfilesPath, '--profile', $Profile, '--platform', 'windows', '--architecture', 'x64')
    foreach ($pack in $Packs) { $arguments += @('--pack', $pack) }
    if ($EssentialsOnly) { $arguments += '--essentials-only' }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Executable @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Get-LegacyPackageIds {
    param([string]$Output)
    return @([regex]::Matches($Output, '(?m)^\[PLANNED\] winget install --id "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
}

function Get-LegacyPacks {
    param([string]$Output)
    $match = [regex]::Match($Output, '(?m)^Packs:\s*(.+)\s*$')
    if (-not $match.Success) { return [string[]]@() }
    return [string[]]@($match.Groups[1].Value.Trim() -split ',\s*' | Where-Object { $_ })
}

function Get-LegacyEstimate {
    param([string]$Output)
    $download = [regex]::Match($Output, 'Estimated Download \(fresh setup\):\r?\n\s+([^\r\n]+)')
    $install = [regex]::Match($Output, 'Estimated Install Time:\r?\n\s+([^\r\n]+)')
    Assert-True $download.Success 'Legacy output is missing the download estimate.'
    Assert-True $install.Success 'Legacy output is missing the install-time estimate.'
    return [pscustomobject]@{ Download = $download.Groups[1].Value.Trim(); InstallTime = $install.Groups[1].Value.Trim() }
}

function Format-EstimatedSize {
    param([double]$Megabytes)
    if ($Megabytes -ge 1024) { return ('{0:N1} GB' -f ($Megabytes / 1024)) }
    return ('{0:N0} MB' -f $Megabytes)
}

function Assert-PlanParity {
    param(
        [string]$GoBinary,
        [string]$PackagesPath,
        [string]$ProfilesPath,
        [string]$Profile,
        [string[]]$Packs,
        [bool]$EssentialsOnly
    )
    $mode = if ($EssentialsOnly) { 'essentials' } else { 'default' }
    $context = "$Profile/$mode packs=$($Packs -join ',')"
    $legacy = Invoke-LegacyPlan -Profile $Profile -Packs $Packs -EssentialsOnly $EssentialsOnly
    Assert-True ($legacy.ExitCode -eq 0) "Legacy planner failed for $context.`n$($legacy.Output)"
    $shadow = Invoke-ShadowPlan -Executable $GoBinary -PackagesPath $PackagesPath -ProfilesPath $ProfilesPath -Profile $Profile -Packs $Packs -EssentialsOnly $EssentialsOnly
    Assert-True ($shadow.ExitCode -eq 0) "Go planner failed for $context.`n$($shadow.Output)"
    $plan = $shadow.Output | ConvertFrom-Json

    $legacyPackageIds = @(Get-LegacyPackageIds $legacy.Output)
    $shadowPackageIds = @($plan.operations | Where-Object { $_.kind -eq 'install' } | ForEach-Object { $_.packageId })
    Assert-True (($legacyPackageIds -join '|') -eq ($shadowPackageIds -join '|')) "Package order differs for $context.`nLegacy: $($legacyPackageIds -join ', ')`nGo: $($shadowPackageIds -join ', ')"
    $legacyPacks = @(Get-LegacyPacks $legacy.Output)
    Assert-True (($legacyPacks -join '|') -eq (@($plan.packIds) -join '|')) "Selected packs differ for $context."

    $legacyEstimate = Get-LegacyEstimate $legacy.Output
    $shadowDownload = "$(Format-EstimatedSize ([double]$plan.estimate.downloadMbMin)) - $(Format-EstimatedSize ([double]$plan.estimate.downloadMbMax))"
    $shadowInstall = "$([Math]::Max(1, [Math]::Ceiling([double]$plan.estimate.installMinutesMin)))-$([Math]::Max(1, [Math]::Ceiling([double]$plan.estimate.installMinutesMax))) minutes"
    Assert-True ($legacyEstimate.Download -eq $shadowDownload) "Download estimate differs for ${context}: '$($legacyEstimate.Download)' vs '$shadowDownload'."
    Assert-True ($legacyEstimate.InstallTime -eq $shadowInstall) "Install estimate differs for ${context}: '$($legacyEstimate.InstallTime)' vs '$shadowInstall'."
    Assert-True ($plan.catalogSha256 -match '^[a-f0-9]{64}$') "Catalog digest is invalid for $context."
    Assert-True ($plan.planId -match '^[a-f0-9-]{36}$') "Plan id is invalid for $context."
    Assert-True (@($plan.operations | Where-Object { $_.kind -eq 'detect' }).Count -eq $legacyPackageIds.Count) "Detect operation count differs for $context."
}

try {
    $goExe = Resolve-GoExecutable
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $catalogRoot = Join-Path $tempRoot 'catalogs'
    $compiled = & $compilerPath -OutputDirectory $catalogRoot
    $env:GOCACHE = Join-Path $tempRoot 'go-cache'
    $env:GOMODCACHE = Join-Path $tempRoot 'go-mod-cache'
    & $goExe test ./...
    Assert-True ($LASTEXITCODE -eq 0) 'Go unit tests failed.'

    $goBinary = Join-Path $tempRoot 'cowebs-setup.exe'
    & $goExe build -trimpath -o $goBinary ./cmd/cowebs-setup
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $goBinary)) 'Go shadow planner build failed.'

    $profiles = @('backend', 'frontend', 'android', 'devops', 'ai', 'cyber', 'game', 'fullstack', 'everything')
    foreach ($profile in $profiles) {
        Assert-PlanParity -GoBinary $goBinary -PackagesPath $compiled.PackageCatalog -ProfilesPath $compiled.ProfileCatalog -Profile $profile -Packs @() -EssentialsOnly $false
        Assert-PlanParity -GoBinary $goBinary -PackagesPath $compiled.PackageCatalog -ProfilesPath $compiled.ProfileCatalog -Profile $profile -Packs @() -EssentialsOnly $true
    }

    Assert-PlanParity -GoBinary $goBinary -PackagesPath $compiled.PackageCatalog -ProfilesPath $compiled.ProfileCatalog -Profile 'backend' -Packs @('backend-python', 'cloud-aws') -EssentialsOnly $false

    $legacyConflict = Invoke-LegacyPlan -Profile 'ai' -Packs @('ai-conda') -EssentialsOnly $false
    $shadowConflict = Invoke-ShadowPlan -Executable $goBinary -PackagesPath $compiled.PackageCatalog -ProfilesPath $compiled.ProfileCatalog -Profile 'ai' -Packs @('ai-conda') -EssentialsOnly $false
    Assert-True ($legacyConflict.ExitCode -ne 0 -and $legacyConflict.Output -match 'Package conflict') 'Legacy planner did not reject the AI environment conflict.'
    Assert-True ($shadowConflict.ExitCode -ne 0 -and $shadowConflict.Output -match 'package conflict') 'Go planner did not reject the AI environment conflict.'

    $first = Invoke-ShadowPlan -Executable $goBinary -PackagesPath $compiled.PackageCatalog -ProfilesPath $compiled.ProfileCatalog -Profile 'everything' -Packs @() -EssentialsOnly $false
    $second = Invoke-ShadowPlan -Executable $goBinary -PackagesPath $compiled.PackageCatalog -ProfilesPath $compiled.ProfileCatalog -Profile 'everything' -Packs @() -EssentialsOnly $false
    Assert-True ($first.ExitCode -eq 0 -and $first.Output -ceq $second.Output) 'Identical planner inputs must produce byte-identical JSON.'

    Write-Host 'PASS: Go shadow planner matches PowerShell across 19 successful scenarios, conflict rejection, and deterministic output.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
