$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-fedora-planning-{0}" -f [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Resolve-GoExecutable {
    if ($env:COWEBS_GO_EXE -and (Test-Path -LiteralPath $env:COWEBS_GO_EXE)) { return $env:COWEBS_GO_EXE }
    $command = Get-Command go -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $workspaceTool = Join-Path $projectRoot '.tmp\go-toolchain\go\bin\go.exe'
    if (Test-Path -LiteralPath $workspaceTool) { return $workspaceTool }
    throw 'Go is required for Fedora planning tests.'
}

function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $compiled = Join-Path $tempRoot 'compiled'
    & (Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1') -OutputDirectory $compiled | Out-Null
    $catalog = Get-Content -LiteralPath (Join-Path $compiled 'package-catalog.v3.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($catalog.packages).Count -eq 86) 'Fedora compilation must preserve all 86 logical packages.'
    Assert-True (@($catalog.packages | Where-Object { $_.providers.fedora }).Count -eq 42) 'Fedora executable-provider count changed.'
    Assert-True (@($catalog.packages | Where-Object { -not $_.providers.fedora }).Count -eq 44) 'Fedora unsupported-result count changed.'
    Assert-True (($catalog.packages | Where-Object id -eq 'node').providers.fedora.packageId -eq 'nodejs24') 'Fedora Node.js provider must work across Fedora 43 and 44.'
    Assert-True (-not ($catalog.packages | Where-Object id -eq 'openjdk').providers.fedora) 'Fedora OpenJDK 21 must remain unsupported when the exact major is unavailable on Fedora 44.'
    Assert-True (-not ($catalog.packages | Where-Object id -eq 'scrcpy').providers.fedora) 'Fedora scrcpy must remain unsupported without an official Fedora provider.'

    $cliPath = Join-Path $tempRoot 'cowebs-setup.exe'
    $build = Invoke-Native -FilePath (Resolve-GoExecutable) -Arguments @('build', '-o', $cliPath, './cmd/cowebs-setup')
    Assert-True ($build.ExitCode -eq 0) "Go CLI build failed: $($build.Stderr)"
    $arguments = @('plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'), '--profiles', (Join-Path $compiled 'profile-catalog.v3.json'), '--profile', 'game', '--platform', 'fedora', '--architecture', 'x64', '--essentials-only', '--json')
    $first = Invoke-Native -FilePath $cliPath -Arguments $arguments
    $second = Invoke-Native -FilePath $cliPath -Arguments $arguments
    Assert-True ($first.ExitCode -eq 0 -and $second.ExitCode -eq 0) "Fedora core plan failed: $($first.Stderr)$($second.Stderr)"
    Assert-True ($first.Stdout -ceq $second.Stdout) 'Fedora core plan JSON is not byte-deterministic.'
    $plan = $first.Stdout | ConvertFrom-Json
    $installs = @($plan.operations | Where-Object { $_.kind -eq 'install' })
    Assert-True ($installs.Count -eq 11) 'Fedora core plan must contain all 11 core installs.'
    Assert-True (($installs.logicalPackageId -join ',') -eq 'git,github-cli,vscode,powershell,windows-terminal,seven-zip,jq,ripgrep,fd,git-lfs,openssl') 'Fedora core plan order changed.'
    Assert-True (($installs | Where-Object logicalPackageId -eq 'github-cli').manager -eq 'dnf') 'GitHub CLI must use its Fedora DNF identity.'
    Assert-True (($installs | Where-Object logicalPackageId -eq 'vscode').manager -eq 'snap') 'VS Code must retain its conditional classic Snap provider.'
    Assert-True (@($plan.operations | Where-Object kind -eq 'configure').Count -eq 4) 'Fedora configuration intents must remain explicit.'

    $unsupported = Invoke-Native -FilePath $cliPath -Arguments @('plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'), '--profiles', (Join-Path $compiled 'profile-catalog.v3.json'), '--profile', 'backend', '--platform', 'fedora', '--architecture', 'x64', '--json')
    Assert-True ($unsupported.ExitCode -eq 1) 'Fedora backend plan must fail closed while Docker Desktop and PostgreSQL remain unsupported.'
    Assert-True ($unsupported.Stderr -match 'unsupported packages for fedora/x64: docker, postgresql') 'Fedora unsupported diagnostics changed or omitted intent.'

    Write-Host 'PASS: Complete Fedora classification, deterministic core planning, and fail-closed diagnostics.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
