$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-release-{0}" -f [guid]::NewGuid().ToString('N'))
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $result = & (Join-Path $projectRoot 'scripts\build-cross-platform.ps1') -Version '6.3.0-dev' -OutputDirectory $tempRoot -ReleaseBaseUrl 'https://github.com/cowebsLB/cowebs-developer-setup/releases/download/v6.3.0-dev'
    Assert-True ($result.ArtifactCount -eq 6) 'Cross-platform build must emit three bundles, one pinned bootstrap, one SBOM, and checksums.'
    $manifest = Get-Content -LiteralPath $result.Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($manifest.schemaVersion -eq 1 -and $manifest.version -eq '6.3.0-dev') 'Release manifest identity changed.'
    Assert-True (@($manifest.artifacts).Count -eq 6) 'Release manifest artifact count changed.'
    foreach ($artifact in @($manifest.artifacts)) {
        $path = Join-Path $tempRoot $artifact.name
        Assert-True (Test-Path -LiteralPath $path) "Manifest artifact '$($artifact.name)' is missing."
        Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $artifact.sha256) "Artifact '$($artifact.name)' digest mismatch."
        Assert-True ((Get-Item -LiteralPath $path).Length -eq $artifact.sizeBytes) "Artifact '$($artifact.name)' size mismatch."
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$artifact.minimumEnvironment)) "Artifact '$($artifact.name)' has no environment contract."
        Assert-True ($artifact.url -notmatch '/(?:refs/heads|raw/main|raw/master|default-branch)/') "Artifact '$($artifact.name)' uses a mutable URL."
    }
    $bootstrap = Get-Content -LiteralPath (Join-Path $tempRoot 'cowebs-install-6.3.0-dev.sh') -Raw -Encoding UTF8
    Assert-True ($bootstrap -notmatch '@(?:VERSION|BASE_URL|LINUX_)') 'Unix bootstrap still contains unresolved build tokens.'
    Assert-True ($bootstrap -match 'sha256sum' -and $bootstrap -match 'releases/download/v6\.3\.0-dev') 'Unix bootstrap must verify pinned release assets.'
    Assert-True ($bootstrap -notmatch '(?i)(raw/main|refs/heads|git clone)') 'Unix bootstrap must not execute mutable default-branch code.'
    $windowsExtract = Join-Path $tempRoot 'windows-extract'
    Expand-Archive -LiteralPath (Join-Path $tempRoot 'cowebs-6.3.0-dev-windows-x64.zip') -DestinationPath $windowsExtract
    $versionOutput = & (Join-Path $windowsExtract 'cowebs.exe') --version
    Assert-True ($LASTEXITCODE -eq 0 -and $versionOutput -eq 'cowebs 6.3.0-dev') 'Built Windows public CLI did not execute with the release version.'
    $linuxEntries = & tar -tzf (Join-Path $tempRoot 'cowebs-6.3.0-dev-linux-x64.tar.gz')
    Assert-True ($LASTEXITCODE -eq 0 -and ($linuxEntries -join "`n") -match 'cowebs' -and ($linuxEntries -join "`n") -match 'catalog/package-catalog.v3.json') 'Linux bundle is missing its binary or deterministic catalogs.'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot 'packaging\debian\control')) 'Debian package metadata is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot 'packaging\rpm\cowebs.spec')) 'RPM package metadata is missing.'
    $wingetInstaller = Get-Content -LiteralPath (Join-Path $result.Winget 'COWebs.CLI.installer.yaml') -Raw -Encoding UTF8
    Assert-True ($wingetInstaller -notmatch '@(?:VERSION|WINDOWS_)' -and $wingetInstaller -match 'releases/download/v6\.3\.0-dev') 'Generated Winget manifest is not pinned to the verified Windows release artifact.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\validate-linux-disposable.sh') -Raw) -match 'COWEBS_DISPOSABLE') 'Disposable validation guard is missing.'
    Write-Host 'PASS: Cross-platform binaries, immutable bootstrap, manifest, checksums, SBOM, and native packaging contracts.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
exit 0
