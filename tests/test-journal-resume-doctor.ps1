$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-journal-test-{0}" -f [guid]::NewGuid().ToString('N'))

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
    throw 'Go is required for the journal and doctor tests.'
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

    # Test 1: Doctor Command (--json)
    $doctorJson = & $cliBinary doctor --packages $packageV3 --profiles $profileV3 --json
    Assert-True ($LASTEXITCODE -eq 0) 'Doctor command --json failed.'
    $report = $doctorJson | ConvertFrom-Json
    Assert-True ($report.checks.Count -ge 3) 'Doctor report must contain diagnostic checks.'

    # Test 2: Journal Status and Resume Operations
    $planPath = Join-Path $tempRoot 'plan-backend.json'
    $planJson = & $cliBinary plan --packages $packageV3 --profiles $profileV3 --profile backend
    Assert-True ($LASTEXITCODE -eq 0) 'Plan generation failed.'
    [IO.File]::WriteAllText($planPath, $planJson, [Text.UTF8Encoding]::new($false))

    $journalPath = Join-Path $tempRoot 'session.jsonl'
    $statePath = Join-Path $tempRoot 'state.json'

    # Run broker writing to journal
    $brokerOut = & $cliBinary broker --plan $planPath --packages $packageV3 --profiles $profileV3 --journal $journalPath --state $statePath --dry-run
    Assert-True ($LASTEXITCODE -eq 0) 'Broker run with journal writing failed.'
    Assert-True (Test-Path -LiteralPath $journalPath) 'Journal file was not created.'

    # Run status command
    $statusJson = & $cliBinary status --journal $journalPath --state $statePath --json
    Assert-True ($LASTEXITCODE -eq 0) 'Status command failed.'
    $statusObj = $statusJson | ConvertFrom-Json
    Assert-True ($statusObj.sessionId -match '^sess-') 'Status must report valid sessionId.'

    # Run resume command
    $resumeJson = & $cliBinary resume --plan $planPath --packages $packageV3 --profiles $profileV3 --journal $journalPath --state $statePath --dry-run --json 2>&1
    Assert-True ($LASTEXITCODE -eq 0) 'Resume command failed.'
    $stateAfterResume = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($stateAfterResume.lastSequence -gt $statusObj.lastSequence) 'Resume must append durable events with increasing sequence numbers.'

    # Test 3: Resume rejects state from a different plan/catalog.
    $stateAfterResume.catalogSha256 = '0000000000000000000000000000000000000000000000000000000000000000'
    [IO.File]::WriteAllText($statePath, ($stateAfterResume | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $mismatchOutput = & $cliBinary resume --plan $planPath --packages $packageV3 --profiles $profileV3 --journal $journalPath --state $statePath --dry-run --json 2>&1
        $mismatchExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-True ($mismatchExit -ne 0) 'Resume must reject state from a different catalog.'
    Assert-True (($mismatchOutput -join "`n") -match 'does not match') 'Resume mismatch error must be explicit.'

    Write-Host 'PASS: Journal, state snapshot, status, resume, and doctor CLI commands.'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
