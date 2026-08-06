$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $projectRoot 'master-setup.bat'
$buildScript = Join-Path $projectRoot 'scripts\build-release.ps1'
$testOutput = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-bootstrap-test-{0}" -f [guid]::NewGuid().ToString('N'))
$tempRoot = Join-Path $env:TEMP 'COWebs.lb'
$originalModulePath = $env:PSModulePath
$restrictedModulePath = Join-Path $testOutput 'empty-modules'

try {
    $artifact = & $buildScript -OutputDirectory $testOutput
    $before = @()
    if (Test-Path -LiteralPath $tempRoot) { $before = @(Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -ExpandProperty FullName) }

    $env:COWEBS_SETUP_BUNDLE_PATH = $artifact.Archive
    $env:COWEBS_SETUP_BUNDLE_SHA256 = $artifact.SHA256
    New-Item -ItemType Directory -Path $restrictedModulePath -Force | Out-Null
    $env:PSModulePath = $restrictedModulePath
    $output = & cmd.exe /d /c "`"$bootstrapPath`" --profile backend --pack backend-python --pack cloud-aws --dry-run --no-config --no-restart" 2>&1
    $exitCode = $LASTEXITCODE
    $joined = $output -join "`n"

    if ($exitCode -ne 0) { throw "Bootstrap dry-run exited with code $exitCode.`n$joined" }
    if ($joined -notmatch 'Master Developer Environment Setup v6\.1\.0') { throw 'Branded v6.1.0 header was not rendered.' }
    if ($joined -notmatch 'Estimated Download \(fresh setup\):') { throw 'Bootstrap did not show the download estimate.' }
    if ($joined -notmatch 'Estimated Install Time:') { throw 'Bootstrap did not show the install-time estimate.' }
    if ($joined -notmatch 'Summary') { throw 'Bootstrap did not show the final summary.' }
    if ($joined -notmatch 'Privilege:\s+(Administrator|Standard user \(preview only\))') { throw 'Bootstrap did not show the current privilege state.' }
    if ($joined -notmatch '20 unique packages selected') { throw 'Profile and repeatable pack options did not resolve 20 packages.' }
    if ($joined -notmatch 'Packs: backend-node, backend-python, cloud-aws') { throw 'Bootstrap did not safely hand explicit packs to the engine.' }
    if ($joined -notmatch 'Planned:\s+20') { throw 'Pack-aware bootstrap dry-run did not finish successfully.' }

    $after = @()
    if (Test-Path -LiteralPath $tempRoot) { $after = @(Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -ExpandProperty FullName) }
    $leaked = @($after | Where-Object { $before -notcontains $_ })
    if ($leaked.Count -gt 0) { throw "Bootstrap left temporary directories: $($leaked -join ', ')" }

    Write-Host 'PASS: release build, checksum verification, extraction, engine handoff, dry-run, and cleanup.'
} finally {
    Remove-Item Env:COWEBS_SETUP_BUNDLE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:COWEBS_SETUP_BUNDLE_SHA256 -ErrorAction SilentlyContinue
    $env:PSModulePath = $originalModulePath
    if (Test-Path -LiteralPath $testOutput) { Remove-Item -LiteralPath $testOutput -Recurse -Force }
}
