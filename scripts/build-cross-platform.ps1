[CmdletBinding()]
param(
    [string]$Version = '6.3.0-dev',
    [string]$OutputDirectory,
    [string]$ReleaseBaseUrl,
    [string]$SourceCommit
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid semantic version '$Version'." }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist\cross-platform' }
if (-not $ReleaseBaseUrl) { $ReleaseBaseUrl = "https://github.com/cowebsLB/cowebs-developer-setup/releases/download/v$Version" }
if ($ReleaseBaseUrl -notmatch '^https://' -or $ReleaseBaseUrl -match '/(?:refs/heads|raw/main|raw/master|default-branch)/') { throw 'ReleaseBaseUrl must identify immutable HTTPS release assets.' }
if (-not $SourceCommit) {
    $SourceCommit = (& git -C $projectRoot rev-parse HEAD).Trim()
}
if ($SourceCommit -notmatch '^[a-fA-F0-9]{40}$') { throw 'SourceCommit must be a full Git commit hash.' }

function Resolve-GoExecutable {
    if ($env:COWEBS_GO_EXE -and (Test-Path -LiteralPath $env:COWEBS_GO_EXE)) { return $env:COWEBS_GO_EXE }
    $command = Get-Command go -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $workspaceTool = Join-Path $projectRoot '.tmp\go-toolchain\go\bin\go.exe'
    if (Test-Path -LiteralPath $workspaceTool) { return $workspaceTool }
    throw 'Go is required. Install the go.mod version or set COWEBS_GO_EXE.'
}

function Write-Utf8Json {
    param($Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 20
    $json = $json -replace "`r?`n", "`n"
    [IO.File]::WriteAllText($Path, ($json + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-ArtifactRecord {
    param([string]$Path, [string]$Platform, [string]$Architecture, [string]$MinimumEnvironment)
    return [pscustomobject][ordered]@{
        name = Split-Path -Leaf $Path
        platform = $Platform
        architecture = $Architecture
        url = "$ReleaseBaseUrl/$(Split-Path -Leaf $Path)"
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        sizeBytes = (Get-Item -LiteralPath $Path).Length
        minimumEnvironment = $MinimumEnvironment
    }
}

$goExecutable = Resolve-GoExecutable
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-cross-platform-{0}" -f [guid]::NewGuid().ToString('N'))
$artifacts = New-Object System.Collections.Generic.List[object]
$previousGoos = $env:GOOS
$previousGoarch = $env:GOARCH
try {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $catalogDirectory = Join-Path $stagingRoot 'catalog'
    & (Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1') -OutputDirectory $catalogDirectory | Out-Null

    foreach ($target in @(
        [pscustomobject]@{ Goos = 'windows'; Goarch = 'amd64'; Platform = 'windows'; Architecture = 'x64'; Extension = '.exe' },
        [pscustomobject]@{ Goos = 'linux'; Goarch = 'amd64'; Platform = 'linux'; Architecture = 'x64'; Extension = '' },
        [pscustomobject]@{ Goos = 'linux'; Goarch = 'arm64'; Platform = 'linux'; Architecture = 'arm64'; Extension = '' }
    )) {
        $bundle = Join-Path $stagingRoot "$($target.Platform)-$($target.Architecture)"
        New-Item -ItemType Directory -Path (Join-Path $bundle 'catalog') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $catalogDirectory 'package-catalog.v3.json') -Destination (Join-Path $bundle 'catalog\package-catalog.v3.json')
        Copy-Item -LiteralPath (Join-Path $catalogDirectory 'profile-catalog.v3.json') -Destination (Join-Path $bundle 'catalog\profile-catalog.v3.json')
        Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $bundle 'LICENSE')
        $binary = Join-Path $bundle ("cowebs" + $target.Extension)
        $env:GOOS = $target.Goos
        $env:GOARCH = $target.Goarch
        & $goExecutable build -trimpath -ldflags "-s -w -X main.version=$Version" -o $binary ./cmd/cowebs
        if ($LASTEXITCODE -ne 0) { throw "Go build failed for $($target.Goos)/$($target.Goarch)." }

        if ($target.Platform -eq 'windows') {
            $archive = Join-Path $OutputDirectory "cowebs-$Version-windows-x64.zip"
            Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -CompressionLevel Optimal -Force
        } else {
            $archive = Join-Path $OutputDirectory "cowebs-$Version-linux-$($target.Architecture).tar.gz"
            & tar -czf $archive -C $bundle .
            if ($LASTEXITCODE -ne 0) { throw "tar failed for Linux $($target.Architecture)." }
        }
        $minimumEnvironment = if ($target.Platform -eq 'windows') { 'Windows 10 or Windows Server 2016 and later; Go runtime preview only' } else { 'Ubuntu 24.04 or Fedora 43-44; see support matrix for architecture evidence' }
        $artifacts.Add((Get-ArtifactRecord -Path $archive -Platform $target.Platform -Architecture $target.Architecture -MinimumEnvironment $minimumEnvironment))
    }

    $linuxX64 = $artifacts | Where-Object { $_.platform -eq 'linux' -and $_.architecture -eq 'x64' } | Select-Object -First 1
    $linuxArm64 = $artifacts | Where-Object { $_.platform -eq 'linux' -and $_.architecture -eq 'arm64' } | Select-Object -First 1
    $windowsX64 = $artifacts | Where-Object { $_.platform -eq 'windows' -and $_.architecture -eq 'x64' } | Select-Object -First 1
    $wingetOutput = Join-Path $OutputDirectory 'winget'
    New-Item -ItemType Directory -Path $wingetOutput -Force | Out-Null
    foreach ($templateName in @('COWebs.CLI.yaml', 'COWebs.CLI.installer.yaml', 'COWebs.CLI.locale.en-US.yaml')) {
        $template = Get-Content -LiteralPath (Join-Path $projectRoot "packaging\winget\$templateName") -Raw -Encoding UTF8
        $rendered = $template.Replace('@VERSION@', $Version).Replace('@WINDOWS_URL@', $windowsX64.url).Replace('@WINDOWS_SHA256@', $windowsX64.sha256)
        [IO.File]::WriteAllText((Join-Path $wingetOutput $templateName), ($rendered -replace "`r?`n", "`n"), [Text.UTF8Encoding]::new($false))
    }
    $bootstrap = Get-Content -LiteralPath (Join-Path $projectRoot 'src\linux\install.sh') -Raw -Encoding UTF8
    $bootstrap = $bootstrap.Replace('@VERSION@', $Version).Replace('@BASE_URL@', $ReleaseBaseUrl.TrimEnd('/')).Replace('@LINUX_X64_SHA256@', $linuxX64.sha256).Replace('@LINUX_ARM64_SHA256@', $linuxArm64.sha256)
    $bootstrapPath = Join-Path $OutputDirectory "cowebs-install-$Version.sh"
    [IO.File]::WriteAllText($bootstrapPath, ($bootstrap -replace "`r?`n", "`n"), [Text.UTF8Encoding]::new($false))
    $artifacts.Add((Get-ArtifactRecord -Path $bootstrapPath -Platform 'portable' -Architecture 'any' -MinimumEnvironment 'POSIX shell with curl, sha256sum, tar, and install'))

    $sbomIndex = 0
    $sbomFiles = @($artifacts | ForEach-Object {
        $sbomIndex++
        [ordered]@{
            fileName = $_.name; SPDXID = "SPDXRef-File-$sbomIndex"
            checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $_.sha256 })
            licenseConcluded = 'NOASSERTION'; copyrightText = 'NOASSERTION'
        }
    })
    $sbom = [ordered]@{
        spdxVersion = 'SPDX-2.3'; dataLicense = 'CC0-1.0'; SPDXID = 'SPDXRef-DOCUMENT'
        name = "cowebs-$Version"; documentNamespace = "https://cowebslb.com/spdx/cowebs/$Version/$SourceCommit"
        creationInfo = [ordered]@{ created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); creators = @('Organization: COWebs.lb', 'Tool: scripts/build-cross-platform.ps1') }
        documentDescribes = @($sbomFiles | ForEach-Object { $_.SPDXID }); files = $sbomFiles
    }
    $sbomPath = Join-Path $OutputDirectory "cowebs-$Version.spdx.json"
    Write-Utf8Json -Value $sbom -Path $sbomPath
    $artifacts.Add((Get-ArtifactRecord -Path $sbomPath -Platform 'portable' -Architecture 'any' -MinimumEnvironment 'JSON reader'))

    $checksumsPath = Join-Path $OutputDirectory 'SHA256SUMS'
    $checksumLines = @($artifacts | Sort-Object name | ForEach-Object { "$($_.sha256)  $($_.name)" })
    [IO.File]::WriteAllText($checksumsPath, (($checksumLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    $artifacts.Add((Get-ArtifactRecord -Path $checksumsPath -Platform 'portable' -Architecture 'any' -MinimumEnvironment 'SHA-256 checksum utility'))

    $manifest = [ordered]@{
        schemaVersion = 1; version = $Version; sourceCommit = $SourceCommit
        publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        artifacts = @($artifacts | ForEach-Object { $_ })
    }
    $manifestPath = Join-Path $OutputDirectory 'release-manifest-v1.json'
    Write-Utf8Json -Value $manifest -Path $manifestPath

    [pscustomobject]@{ Version = $Version; OutputDirectory = $OutputDirectory; Manifest = $manifestPath; ArtifactCount = $artifacts.Count; Checksums = $checksumsPath; SBOM = $sbomPath; Winget = $wingetOutput }
} finally {
    $env:GOOS = $previousGoos
    $env:GOARCH = $previousGoarch
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
