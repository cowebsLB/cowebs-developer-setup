$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-broker-test-{0}" -f [guid]::NewGuid().ToString('N'))

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
    throw 'Go is required for the broker tests.'
}

try {
    $goExe = Resolve-GoExecutable
    $cliBinary = Join-Path $tempRoot 'cowebs-setup.exe'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    & $goExe build -o $cliBinary (Join-Path $projectRoot 'cmd\cowebs-setup')
    Assert-True ($LASTEXITCODE -eq 0) 'Failed to build cowebs-setup CLI.'

    $v3Directory = Join-Path $tempRoot 'v3'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compilerPath -OutputDirectory $v3Directory | Out-Null
    $packageV3 = Join-Path $v3Directory 'package-catalog.v3.json'
    $profileV3 = Join-Path $v3Directory 'profile-catalog.v3.json'

    # Test 1: Generate Plan & Run Broker in DryRun Mode
    $planPath = Join-Path $tempRoot 'plan-backend.json'
    $planJson = & $cliBinary plan --packages $packageV3 --profiles $profileV3 --profile backend
    Assert-True ($LASTEXITCODE -eq 0) 'Go plan generation failed.'
    [IO.File]::WriteAllText($planPath, $planJson, [Text.UTF8Encoding]::new($false))

    $brokerOutput = & $cliBinary broker --plan $planPath --packages $packageV3 --profiles $profileV3 --dry-run 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Go broker dry-run failed: $($brokerOutput -join ' ')"
    $brokerLines = @($brokerOutput -split "`r?`n" | Where-Object { $_ })
    Assert-True ($brokerLines.Count -gt 5) 'Expected multiple execution events from broker.'

    $firstEvent = $brokerLines[0] | ConvertFrom-Json
    Assert-True ($firstEvent.schemaVersion -eq 1) 'Event schema version must be 1.'
    Assert-True ($firstEvent.type -eq 'operation') 'Event type must be operation.'
    Assert-True ($firstEvent.status -eq 'started') 'First event status must be started.'

    # Test 2: Security Violation - Mismatched Catalog SHA256
    $tamperedPlanObject = $planJson | ConvertFrom-Json
    $tamperedPlanObject.catalogSha256 = '0000000000000000000000000000000000000000000000000000000000000000'
    $tamperedPlanPath = Join-Path $tempRoot 'plan-tampered-hash.json'
    [IO.File]::WriteAllText($tamperedPlanPath, ($tamperedPlanObject | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $tamperedOutput = & $cliBinary broker --plan $tamperedPlanPath --packages $packageV3 --profiles $profileV3 --dry-run 2>&1
        $tamperedExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-True ($tamperedExit -ne 0) 'Broker must reject plan with mismatched catalog SHA256.'
    Assert-True (($tamperedOutput -join "`n") -match 'catalog digest mismatch') 'Error message must specify catalog digest mismatch.'

    # Test 3: Security Violation - Configure operation in broker
    $tamperedPlanObject2 = $planJson | ConvertFrom-Json
    $tamperedPlanObject2.operations += [pscustomobject]@{
        id = 'configure:git'
        kind = 'configure'
        logicalPackageId = 'git'
        configurationIntent = 'git'
        privilege = 'elevated'
        dependsOn = @()
    }
    $tamperedPlanPath2 = Join-Path $tempRoot 'plan-tampered-configure.json'
    [IO.File]::WriteAllText($tamperedPlanPath2, ($tamperedPlanObject2 | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

    $ErrorActionPreference = 'Continue'
    try {
        $tamperedOutput2 = & $cliBinary broker --plan $tamperedPlanPath2 --packages $packageV3 --profiles $profileV3 --dry-run 2>&1
        $tamperedExit2 = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-True ($tamperedExit2 -ne 0) 'Broker must reject configure operations in elevated plan.'
    Assert-True (($tamperedOutput2 -join "`n") -match 'not the canonical plan') 'Error message must reject non-canonical configure operation.'

    # Test 4: Security Violation - Unknown plan field
    $unknownFieldJson = $planJson.TrimEnd() -replace '\}\s*$', ',"command":"calc.exe"}'
    $unknownFieldPath = Join-Path $tempRoot 'plan-unknown-field.json'
    [IO.File]::WriteAllText($unknownFieldPath, $unknownFieldJson, [Text.UTF8Encoding]::new($false))
    $ErrorActionPreference = 'Continue'
    try {
        $unknownOutput = & $cliBinary broker --plan $unknownFieldPath --packages $packageV3 --profiles $profileV3 --dry-run 2>&1
        $unknownExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-True ($unknownExit -ne 0) 'Broker must reject unknown plan fields.'
    Assert-True (($unknownOutput -join "`n") -match 'unknown field') 'Unknown plan field rejection must be explicit.'

    Write-Host 'PASS: Windows provider adapter and one-shot privileged broker security invariants.'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
