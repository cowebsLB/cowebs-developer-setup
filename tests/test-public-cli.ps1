$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-public-cli-{0}" -f [guid]::NewGuid().ToString('N'))

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Resolve-GoExecutable {
    if ($env:COWEBS_GO_EXE -and (Test-Path -LiteralPath $env:COWEBS_GO_EXE)) { return $env:COWEBS_GO_EXE }
    $command = Get-Command go -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $workspaceTool = Join-Path $projectRoot '.tmp\go-toolchain\go\bin\go.exe'
    if (Test-Path -LiteralPath $workspaceTool) { return $workspaceTool }
    throw 'Go is required for public CLI tests.'
}
function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath; $start.WorkingDirectory = $projectRoot; $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd(); $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $catalog = Join-Path $tempRoot 'catalog'
    & (Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1') -OutputDirectory $catalog | Out-Null
    $binary = Join-Path $tempRoot 'cowebs.exe'
    $build = Invoke-Native -FilePath (Resolve-GoExecutable) -Arguments @('build', '-trimpath', '-o', $binary, './cmd/cowebs')
    Assert-True ($build.ExitCode -eq 0) "Public CLI build failed: $($build.Stderr)"

    $version = Invoke-Native -FilePath $binary -Arguments @('--version')
    Assert-True ($version.ExitCode -eq 0 -and $version.Stdout.Trim() -eq 'cowebs 6.3.0-dev') 'Public version contract changed.'
    foreach ($shell in @('bash', 'zsh', 'powershell')) {
        $completion = Invoke-Native -FilePath $binary -Arguments @('completion', $shell)
        Assert-True ($completion.ExitCode -eq 0 -and $completion.Stdout -match 'cowebs') "Completion generation failed for $shell."
    }

    $arguments = @('plan', 'dev-setup', '--packages', (Join-Path $catalog 'package-catalog.v3.json'), '--profiles', (Join-Path $catalog 'profile-catalog.v3.json'), '--profile', 'game', '--essentials-only', '--platform', 'fedora', '--architecture', 'x64', '--json')
    $first = Invoke-Native -FilePath $binary -Arguments $arguments
    $second = Invoke-Native -FilePath $binary -Arguments $arguments
    Assert-True ($first.ExitCode -eq 0 -and $first.Stdout -ceq $second.Stdout) 'Public Fedora plan must be byte-deterministic.'
    $plan = $first.Stdout | ConvertFrom-Json
    Assert-True ($plan.platform -eq 'fedora' -and @($plan.operations | Where-Object kind -eq 'install').Count -eq 11) 'Public plan did not preserve Fedora core intent.'
    Assert-True (@($plan.operations | Where-Object kind -eq 'ensure-manager').Count -eq 1) 'Public plan must expose the typed Snap manager installation prerequisite.'

    $unknown = Invoke-Native -FilePath $binary -Arguments @('plan', 'other-product')
    Assert-True ($unknown.ExitCode -eq 1 -and $unknown.Stderr -match 'dev-setup') 'Unknown-product diagnostics changed.'
    $unsupported = Invoke-Native -FilePath $binary -Arguments @('plan', 'dev-setup', '--packages', (Join-Path $catalog 'package-catalog.v3.json'), '--profiles', (Join-Path $catalog 'profile-catalog.v3.json'), '--profile', 'backend', '--platform', 'fedora', '--architecture', 'x64', '--json')
    Assert-True ($unsupported.ExitCode -eq 3 -and $unsupported.Stderr -match 'docker, postgresql') 'Structured unsupported-package exit contract changed.'

    Write-Host 'PASS: Public cowebs CLI grammar, dispatch, completions, deterministic planning, and exit contracts.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
exit 0
