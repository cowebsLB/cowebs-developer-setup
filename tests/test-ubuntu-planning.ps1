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

function Write-Utf8Json {
    param($Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 20
    $json = $json -replace "`r?`n", "`n"
    [IO.File]::WriteAllText($Path, ($json + "`n"), [Text.UTF8Encoding]::new($false))
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

    $profiles = Get-Content -LiteralPath $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $cliPath = Join-Path $tempRoot 'cowebs-setup.exe'
    $goExecutable = Resolve-GoExecutable
    $build = Invoke-Native -FilePath $goExecutable -Arguments @('build', '-o', $cliPath, './cmd/cowebs-setup')
    Assert-True ($build.ExitCode -eq 0) "Go CLI build failed: $($build.Stderr)"

    $planArguments = @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', (Join-Path $compiled 'profile-catalog.v3.json'),
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
    Assert-True ($installs.Count -eq 11) 'Ubuntu core plan must contain all 11 core installs.'
    Assert-True (($installs.logicalPackageId -join ',') -eq ($profiles.corePackages -join ',')) 'Ubuntu core install order changed.'
    Assert-True (($installs | Where-Object { $_.logicalPackageId -eq 'vscode' }).manager -eq 'snap') 'VS Code must use the reviewed Snap provider.'
    Assert-True (($installs | Where-Object { $_.logicalPackageId -eq 'windows-terminal' }).packageId -eq 'gnome-terminal') 'The terminal alternative mapping changed.'
    $githubInstall = $installs | Where-Object { $_.logicalPackageId -eq 'github-cli' } | Select-Object -First 1
    Assert-True ($githubInstall.packageId -eq 'gh' -and $githubInstall.manager -eq 'apt-get') 'GitHub CLI must use its official APT provider.'
    Assert-True (($githubInstall.dependsOn -join ',') -eq 'detect:github-cli,prerequisite:apt-get:refresh') 'GitHub CLI install must wait for detection and the typed APT refresh.'
    $prerequisites = @($plan.operations | Where-Object { $_.kind -in @('ensure-repository-key', 'ensure-apt-repository', 'refresh-package-index') })
    Assert-True (($prerequisites.kind -join ',') -eq 'ensure-repository-key,ensure-apt-repository,refresh-package-index') 'Typed GitHub repository prerequisite order changed.'
    Assert-True ($prerequisites[0].sha256 -eq '6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b') 'GitHub keyring digest changed.'
    Assert-True ($prerequisites[1].repositoryArchitecture -eq 'amd64') 'Ubuntu x64 must map to the APT amd64 architecture.'
    Assert-True (($prerequisites[2].dependsOn -join ',') -eq 'prerequisite:github-cli-apt:repository') 'APT refresh must be emitted once after repository setup.'
    Assert-True (@($plan.operations | Where-Object { $_.kind -eq 'configure' }).Count -eq 4) 'Linux configuration intents must remain explicit in the plan.'

    $unsupported = Invoke-Native -FilePath $cliPath -Arguments @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', (Join-Path $compiled 'profile-catalog.v3.json'),
        '--profile', 'game', '--platform', 'ubuntu', '--architecture', 'arm64',
        '--essentials-only', '--json'
    )
    Assert-True ($unsupported.ExitCode -eq 1) 'Ubuntu arm64 must fail closed while the reviewed VS Code and PowerShell Snap mappings remain x64-only.'
    Assert-True ($unsupported.Stderr.Trim() -eq 'ERROR: unsupported packages for ubuntu/arm64: vscode, powershell') 'Ubuntu arm64 unsupported-package diagnostic changed or omitted intent.'

    $runtimeProfiles = Get-Content -LiteralPath (Join-Path $compiled 'profile-catalog.v3.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-runtime-supported'
        name = 'Ubuntu supported runtime slice'
        extends = @()
        packageIds = @('node', 'openjdk', 'dotnet-sdk', 'go', 'rustup')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-runtime-unsupported'
        name = 'Ubuntu unsupported runtime diagnostics'
        extends = @()
        packageIds = @('python', 'ruff', 'php', 'bun', 'deno', 'yarn', 'pnpm', 'docker')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfilesPath = Join-Path $tempRoot 'runtime-profile-catalog.v3.json'
    Write-Utf8Json -Value $runtimeProfiles -Path $runtimeProfilesPath

    $runtimeArguments = @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-runtime-supported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    $runtimeFirst = Invoke-Native -FilePath $cliPath -Arguments $runtimeArguments
    $runtimeSecond = Invoke-Native -FilePath $cliPath -Arguments $runtimeArguments
    Assert-True ($runtimeFirst.ExitCode -eq 0 -and $runtimeSecond.ExitCode -eq 0) "Ubuntu runtime slice failed: $($runtimeFirst.Stderr)$($runtimeSecond.Stderr)"
    Assert-True ($runtimeFirst.Stdout -ceq $runtimeSecond.Stdout) 'Ubuntu runtime slice plan JSON is not byte-deterministic.'
    $runtimePlan = $runtimeFirst.Stdout | ConvertFrom-Json
    $runtimeInstalls = @($runtimePlan.operations | Where-Object { $_.kind -eq 'install' })
    Assert-True ($runtimeInstalls.Count -eq 16) 'Ubuntu runtime slice must contain the 11 core installs plus five reviewed runtime installs.'
    Assert-True (($runtimeInstalls[-5..-1].logicalPackageId -join ',') -eq 'node,openjdk,dotnet-sdk,go,rustup') 'Ubuntu runtime install order changed.'
    $goInstall = $runtimeInstalls | Where-Object { $_.logicalPackageId -eq 'go' } | Select-Object -First 1
    Assert-True ($goInstall.manager -eq 'snap' -and ($goInstall.installOptions -join ',') -eq '--classic') 'Go must use the Canonical classic Snap provider.'
    Assert-True (@($runtimePlan.operations | Where-Object { $_.kind -eq 'refresh-package-index' }).Count -eq 1) 'The expanded runtime plan must still refresh APT metadata exactly once.'

    $runtimeUnsupported = Invoke-Native -FilePath $cliPath -Arguments @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-runtime-unsupported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    Assert-True ($runtimeUnsupported.ExitCode -eq 1) 'The unsupported Ubuntu runtime slice must fail closed.'
    Assert-True ($runtimeUnsupported.Stderr.Trim() -eq 'ERROR: unsupported packages for ubuntu/x64: python, ruff, php, bun, deno, yarn, pnpm, docker') 'Ubuntu runtime unsupported-package diagnostics changed or omitted selected intent.'

    Write-Host 'PASS: Ubuntu core and runtime-slice compilation, typed repository planning, deterministic JSON, and fail-closed diagnostics.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
