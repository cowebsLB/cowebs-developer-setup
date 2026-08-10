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
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-productivity-supported'
        name = 'Ubuntu supported database, client, browser, networking, and Android slice'
        extends = @()
        packageIds = @('postgresql', 'bruno', 'postman', 'redis-insight', 'chrome', 'firefox', 'cloudflared', 'ngrok', 'scrcpy')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-productivity-unsupported'
        name = 'Ubuntu unsupported database, client, design, and Android diagnostics'
        extends = @()
        packageIds = @('dbeaver', 'mongodb-compass', 'mysql-workbench', 'figma', 'android-studio')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-infra-supported'
        name = 'Ubuntu supported Kubernetes, IaC, automation, and security slice'
        extends = @()
        packageIds = @('kubectl', 'helm', 'yq', 'kubectx', 'trivy', 'opentofu', 'terraform', 'vault', 'packer', 'task', 'age')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-infra-unsupported'
        name = 'Ubuntu unsupported Windows-host, Kubernetes, IaC, and secrets diagnostics'
        extends = @()
        packageIds = @('wsl', 'ubuntu-wsl', 'k9s', 'kind', 'flux', 'tflint', 'sops')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-final-supported'
        name = 'Ubuntu supported cloud, data, security, and game tooling slice'
        extends = @()
        packageIds = @('aws-cli', 'azure-cli', 'google-cloud-cli', 'dvc', 'r', 'nmap', 'wireshark', 'unity-hub', 'godot', 'blender', 'krita', 'audacity', 'obs-studio', 'inkscape', 'gimp', 'lmms', 'tiled', 'blockbench')
        recommendedPackIds = @()
        optionalPackIds = @()
    }
    $runtimeProfiles.profiles += [pscustomobject][ordered]@{
        id = 'ubuntu-final-unsupported'
        name = 'Ubuntu unsupported cloud, data, security, and game tooling diagnostics'
        extends = @()
        packageIds = @('jupyterlab', 'ollama', 'rstudio', 'sysinternals', 'zap', 'burp-community', 'kali-wsl', 'epic-games-launcher', 'visual-studio-game', 'renderdoc')
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

    $productivityArguments = @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-productivity-supported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    $productivityFirst = Invoke-Native -FilePath $cliPath -Arguments $productivityArguments
    $productivitySecond = Invoke-Native -FilePath $cliPath -Arguments $productivityArguments
    Assert-True ($productivityFirst.ExitCode -eq 0 -and $productivitySecond.ExitCode -eq 0) "Ubuntu productivity slice failed: $($productivityFirst.Stderr)$($productivitySecond.Stderr)"
    Assert-True ($productivityFirst.Stdout -ceq $productivitySecond.Stdout) 'Ubuntu productivity slice plan JSON is not byte-deterministic.'
    $productivityPlan = $productivityFirst.Stdout | ConvertFrom-Json
    $productivityInstalls = @($productivityPlan.operations | Where-Object { $_.kind -eq 'install' })
    Assert-True ($productivityInstalls.Count -eq 20) 'Ubuntu productivity slice must contain the 11 core installs plus nine reviewed installs.'
    Assert-True (($productivityInstalls[-9..-1].logicalPackageId -join ',') -eq 'postgresql,bruno,postman,redis-insight,chrome,firefox,cloudflared,ngrok,scrcpy') 'Ubuntu productivity install order changed.'
    $brunoInstall = $productivityInstalls | Where-Object { $_.logicalPackageId -eq 'bruno' } | Select-Object -First 1
    Assert-True ($brunoInstall.manager -eq 'flatpak' -and $brunoInstall.source -eq 'flathub' -and $brunoInstall.scope -eq 'user') 'Bruno must use the reviewed user-scoped Flathub provider.'
    $redisInsightInstall = $productivityInstalls | Where-Object { $_.logicalPackageId -eq 'redis-insight' } | Select-Object -First 1
    Assert-True ($redisInsightInstall.manager -eq 'snap' -and $redisInsightInstall.packageId -eq 'redisinsight') 'Redis Insight must use its documented Snap provider.'
    $productivityPrerequisites = @($productivityPlan.operations | Where-Object { $_.kind -in @('ensure-repository-key', 'ensure-apt-repository', 'refresh-package-index') })
    Assert-True (@($productivityPrerequisites | Where-Object { $_.kind -eq 'ensure-repository-key' }).Count -eq 5) 'The productivity plan must include the core GitHub key plus four slice repository keys.'
    Assert-True (@($productivityPrerequisites | Where-Object { $_.kind -eq 'ensure-apt-repository' }).Count -eq 5) 'The productivity plan must include the core GitHub repository plus four slice repositories.'
    Assert-True (@($productivityPrerequisites | Where-Object { $_.kind -eq 'refresh-package-index' }).Count -eq 1) 'All Ubuntu APT prerequisites must share one package-index refresh.'

    $productivityUnsupported = Invoke-Native -FilePath $cliPath -Arguments @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-productivity-unsupported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    Assert-True ($productivityUnsupported.ExitCode -eq 1) 'The unsupported Ubuntu productivity slice must fail closed.'
    Assert-True ($productivityUnsupported.Stderr.Trim() -eq 'ERROR: unsupported packages for ubuntu/x64: dbeaver, mongodb-compass, mysql-workbench, figma, android-studio') 'Ubuntu productivity unsupported-package diagnostics changed or omitted selected intent.'

    $infraArguments = @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-infra-supported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    $infraFirst = Invoke-Native -FilePath $cliPath -Arguments $infraArguments
    $infraSecond = Invoke-Native -FilePath $cliPath -Arguments $infraArguments
    Assert-True ($infraFirst.ExitCode -eq 0 -and $infraSecond.ExitCode -eq 0) "Ubuntu infrastructure slice failed: $($infraFirst.Stderr)$($infraSecond.Stderr)"
    Assert-True ($infraFirst.Stdout -ceq $infraSecond.Stdout) 'Ubuntu infrastructure slice plan JSON is not byte-deterministic.'
    $infraPlan = $infraFirst.Stdout | ConvertFrom-Json
    $infraInstalls = @($infraPlan.operations | Where-Object { $_.kind -eq 'install' })
    Assert-True ($infraInstalls.Count -eq 22) 'Ubuntu infrastructure slice must contain the 11 core installs plus eleven reviewed installs.'
    Assert-True (($infraInstalls[-11..-1].logicalPackageId -join ',') -eq 'kubectl,helm,yq,kubectx,trivy,opentofu,terraform,vault,packer,task,age') 'Ubuntu infrastructure install order changed.'
    foreach ($packageId in @('kubectl', 'helm', 'opentofu', 'task')) {
        $install = $infraInstalls | Where-Object { $_.logicalPackageId -eq $packageId } | Select-Object -First 1
        Assert-True ($install.manager -eq 'snap' -and ($install.installOptions -join ',') -eq '--classic') "Package '$packageId' must use its reviewed classic Snap provider."
    }
    $hashicorpInstalls = @($infraInstalls | Where-Object { $_.logicalPackageId -in @('terraform', 'vault', 'packer') })
    Assert-True ($hashicorpInstalls.Count -eq 3 -and @($hashicorpInstalls | Where-Object { ($_.dependsOn -join ',') -notmatch 'prerequisite:apt-get:refresh' }).Count -eq 0) 'All HashiCorp installs must share the typed APT refresh dependency.'
    $infraPrerequisites = @($infraPlan.operations | Where-Object { $_.kind -in @('ensure-repository-key', 'ensure-apt-repository', 'refresh-package-index') })
    Assert-True (@($infraPrerequisites | Where-Object { $_.kind -eq 'ensure-repository-key' }).Count -eq 3) 'The infrastructure plan must include GitHub, Trivy, and HashiCorp repository keys.'
    Assert-True (@($infraPrerequisites | Where-Object { $_.kind -eq 'ensure-apt-repository' }).Count -eq 3) 'The infrastructure plan must include GitHub, Trivy, and HashiCorp repositories.'
    Assert-True (@($infraPrerequisites | Where-Object { $_.kind -eq 'refresh-package-index' }).Count -eq 1) 'All infrastructure APT prerequisites must share one package-index refresh.'

    $infraUnsupported = Invoke-Native -FilePath $cliPath -Arguments @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-infra-unsupported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    Assert-True ($infraUnsupported.ExitCode -eq 1) 'The unsupported Ubuntu infrastructure slice must fail closed.'
    Assert-True ($infraUnsupported.Stderr.Trim() -eq 'ERROR: unsupported packages for ubuntu/x64: wsl, ubuntu-wsl, k9s, docker, kind, flux, tflint, sops') 'Ubuntu infrastructure unsupported-package diagnostics changed or omitted selected dependency intent.'

    $finalArguments = @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-final-supported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    $finalFirst = Invoke-Native -FilePath $cliPath -Arguments $finalArguments
    $finalSecond = Invoke-Native -FilePath $cliPath -Arguments $finalArguments
    Assert-True ($finalFirst.ExitCode -eq 0 -and $finalSecond.ExitCode -eq 0) "Ubuntu final supported slice failed: $($finalFirst.Stderr)$($finalSecond.Stderr)"
    Assert-True ($finalFirst.Stdout -ceq $finalSecond.Stdout) 'Ubuntu final supported slice plan JSON is not byte-deterministic.'
    $finalPlan = $finalFirst.Stdout | ConvertFrom-Json
    $finalInstalls = @($finalPlan.operations | Where-Object { $_.kind -eq 'install' })
    Assert-True ($finalInstalls.Count -eq 29) 'Ubuntu final supported slice must contain the 11 core installs plus eighteen reviewed installs.'
    Assert-True (($finalInstalls[-18..-1].logicalPackageId -join ',') -eq 'aws-cli,azure-cli,google-cloud-cli,dvc,r,nmap,wireshark,unity-hub,godot,blender,krita,audacity,obs-studio,inkscape,gimp,lmms,tiled,blockbench') 'Ubuntu final supported install order changed.'
    foreach ($packageId in @('aws-cli', 'dvc')) {
        $install = $finalInstalls | Where-Object { $_.logicalPackageId -eq $packageId } | Select-Object -First 1
        Assert-True ($install.manager -eq 'snap' -and ($install.installOptions -join ',') -eq '--classic') "Package '$packageId' must use its reviewed classic Snap provider."
    }
    foreach ($packageId in @('godot', 'obs-studio', 'gimp', 'blockbench')) {
        $install = $finalInstalls | Where-Object { $_.logicalPackageId -eq $packageId } | Select-Object -First 1
        Assert-True ($install.manager -eq 'flatpak' -and $install.source -eq 'flathub' -and $install.scope -eq 'user') "Package '$packageId' must use its reviewed user-scoped Flathub provider."
    }
    $finalPrerequisites = @($finalPlan.operations | Where-Object { $_.kind -in @('ensure-repository-key', 'ensure-apt-repository', 'refresh-package-index') })
    Assert-True (@($finalPrerequisites | Where-Object { $_.kind -eq 'ensure-repository-key' }).Count -eq 4) 'The final supported plan must include GitHub, Azure CLI, Google Cloud CLI, and Unity Hub repository keys.'
    Assert-True (@($finalPrerequisites | Where-Object { $_.kind -eq 'ensure-apt-repository' }).Count -eq 4) 'The final supported plan must include GitHub, Azure CLI, Google Cloud CLI, and Unity Hub repositories.'
    Assert-True (@($finalPrerequisites | Where-Object { $_.kind -eq 'refresh-package-index' }).Count -eq 1) 'All final-slice APT prerequisites must share one package-index refresh.'
    foreach ($packageId in @('azure-cli', 'google-cloud-cli', 'unity-hub')) {
        $install = $finalInstalls | Where-Object { $_.logicalPackageId -eq $packageId } | Select-Object -First 1
        Assert-True (($install.dependsOn -join ',') -match 'prerequisite:apt-get:refresh') "Package '$packageId' must depend on the shared typed APT refresh."
    }

    $finalUnsupported = Invoke-Native -FilePath $cliPath -Arguments @(
        'plan', '--packages', (Join-Path $compiled 'package-catalog.v3.json'),
        '--profiles', $runtimeProfilesPath, '--profile', 'ubuntu-final-unsupported',
        '--platform', 'ubuntu', '--architecture', 'x64', '--json'
    )
    Assert-True ($finalUnsupported.ExitCode -eq 1) 'The final unsupported Ubuntu slice must fail closed.'
    Assert-True ($finalUnsupported.Stderr.Trim() -eq 'ERROR: unsupported packages for ubuntu/x64: jupyterlab, ollama, rstudio, sysinternals, zap, burp-community, wsl, kali-wsl, epic-games-launcher, visual-studio-game, renderdoc') 'Ubuntu final unsupported-package diagnostics changed or omitted dependency intent.'

    Write-Host 'PASS: Complete Ubuntu catalog compilation, typed repository planning, deterministic JSON, and fail-closed diagnostics.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
