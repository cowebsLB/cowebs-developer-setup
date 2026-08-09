$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1'
$packagesPath = Join-Path $projectRoot 'config\packages.json'
$profilesPath = Join-Path $projectRoot 'config\profiles.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-ubuntu-planning-{0}" -f [guid]::NewGuid().ToString('N'))

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
    throw 'Go is required for Ubuntu planning tests. Install the go.mod version or set COWEBS_GO_EXE.'
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
    & $compilerPath -OutputDirectory $compiled | Out-Null

    $boundedProfiles = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $boundedProfiles.corePackages = @(
        'git', 'vscode', 'powershell', 'windows-terminal', 'seven-zip',
        'jq', 'ripgrep', 'fd', 'git-lfs', 'openssl'
    )
    $boundedProfilesPath = Join-Path $tempRoot 'bounded-profiles-v2.json'
    $boundedProfiles | ConvertTo-Json -Depth 20 | ForEach-Object {
        [IO.File]::WriteAllText($boundedProfilesPath, $_, [Text.UTF8Encoding]::new($false))
    }
    $boundedCompiled = Join-Path $tempRoot 'bounded-compiled'
    & $compilerPath -PackagesPath $packagesPath -ProfilesPath $boundedProfilesPath -OutputDirectory $boundedCompiled | Out-Null

    $cliPath = Join-Path $tempRoot 'cowebs-setup.exe'
    $goExecutable = Resolve-GoExecutable
    $build = Invoke-Native -FilePath $goExecutable -Arguments @('build', '-o', $cliPath, './cmd/cowebs-setup')
    Assert-True ($build.ExitCode -eq 0) "Go CLI build failed: $($build.Stderr)"

    $planArguments = @(
        'plan', '--packages', (Join-Path $boundedCompiled 'package-catalog.v3.json'),
        '--profiles', (Join-Path $boundedCompiled 'profile-catalog.v3.json'),
        '--profile', 'game', '--platform', 'ubuntu', '--architecture', 'x64',
        '--essentials-only', '--json'
    )
    $first = Invoke-Native -FilePath $cliPath -Arguments $planArguments
    $second = Invoke-Native -FilePath $cliPath -Arguments $planArguments
    Assert-True ($first.ExitCode -eq 0 -and $second.ExitCode -eq 0) "Bounded Ubuntu plan failed: $($first.Stderr)$($second.Stderr)"
    Assert-True ($first.Stdout -ceq $second.Stdout) 'Bounded Ubuntu plan JSON is not byte-deterministic.'

    $plan = $first.Stdout | ConvertFrom-Json
    Assert-True ($plan.platform -eq 'ubuntu' -and $plan.architecture -eq 'x64') 'Bounded plan target changed.'
    $installs = @($plan.operations | Where-Object { $_.kind -eq 'install' })
    Assert-True ($installs.Count -eq 10) 'Bounded Ubuntu plan must contain ten supported core installs.'
    Assert-True (($installs.logicalPackageId -join ',') -eq ($boundedProfiles.corePackages -join ',')) 'Bounded Ubuntu install order changed.'
    Assert-True (($installs | Where-Object { $_.logicalPackageId -eq 'vscode' }).manager -eq 'snap') 'VS Code must use the reviewed Snap provider.'
    Assert-True (($installs | Where-Object { $_.logicalPackageId -eq 'windows-terminal' }).packageId -eq 'gnome-terminal') 'The terminal alternative mapping changed.'
    Assert-True (@($plan.operations | Where-Object { $_.kind -eq 'configure' }).Count -eq 3) 'Unsupported Linux configuration intents must remain explicit in the plan.'

    $unsupported = Invoke-Native -FilePath $cliPath -Arguments @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', (Join-Path $compiled 'profile-catalog.v3.json'),
        '--profile', 'game', '--platform', 'ubuntu', '--architecture', 'x64',
        '--essentials-only', '--json'
    )
    Assert-True ($unsupported.ExitCode -eq 1) 'The real Ubuntu essentials plan must fail closed while GitHub CLI is unsupported.'
    Assert-True ($unsupported.Stderr.Trim() -eq 'ERROR: unsupported packages for ubuntu/x64: github-cli') 'Ubuntu unsupported-package diagnostic changed or omitted intent.'

    Write-Host 'PASS: bounded Ubuntu compilation and deterministic planning with fail-closed unsupported diagnostics.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
