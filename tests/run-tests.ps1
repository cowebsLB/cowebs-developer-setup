$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot

& (Join-Path $testRoot 'test-architecture-foundation.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-ubuntu-planning.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-fedora-planning.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-go-shadow-planner.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-windows-broker.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-journal-resume-doctor.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-public-cli.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-master-setup.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-bootstrap.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $testRoot 'test-cross-platform-release.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'PASS: complete COWebs.lb developer setup test suite.' -ForegroundColor Green
exit 0
