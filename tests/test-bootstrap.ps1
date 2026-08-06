$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $projectRoot 'master-setup.bat'
$buildScript = Join-Path $projectRoot 'scripts\build-release.ps1'
$testOutput = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-bootstrap-test-{0}" -f [guid]::NewGuid().ToString('N'))
$tempRoot = Join-Path $env:TEMP 'COWebs.lb'

try {
    $artifact = & $buildScript -OutputDirectory $testOutput
    $before = @()
    if (Test-Path -LiteralPath $tempRoot) { $before = @(Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -ExpandProperty FullName) }

    $env:COWEBS_SETUP_BUNDLE_PATH = $artifact.Archive
    $env:COWEBS_SETUP_BUNDLE_SHA256 = $artifact.SHA256
    $output = & cmd.exe /d /c "`"$bootstrapPath`" --profile everything --dry-run --no-config --no-restart" 2>&1
    $exitCode = $LASTEXITCODE
    $joined = $output -join "`n"

    if ($exitCode -ne 0) { throw "Bootstrap dry-run exited with code $exitCode.`n$joined" }
    if ($joined -notmatch 'Master Developer Environment Setup v5\.0\.0') { throw 'Branded v5.0.0 header was not rendered.' }
    if ($joined -notmatch '26 unique packages selected') { throw 'Everything profile did not resolve 26 unique packages.' }
    if ($joined -notmatch 'Planned:\s+26') { throw 'Everything bootstrap dry-run did not finish successfully.' }

    $after = @()
    if (Test-Path -LiteralPath $tempRoot) { $after = @(Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -ExpandProperty FullName) }
    $leaked = @($after | Where-Object { $before -notcontains $_ })
    if ($leaked.Count -gt 0) { throw "Bootstrap left temporary directories: $($leaked -join ', ')" }

    Write-Host 'PASS: release build, checksum verification, extraction, engine handoff, dry-run, and cleanup.'
} finally {
    Remove-Item Env:COWEBS_SETUP_BUNDLE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:COWEBS_SETUP_BUNDLE_SHA256 -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testOutput) { Remove-Item -LiteralPath $testOutput -Recurse -Force }
}
