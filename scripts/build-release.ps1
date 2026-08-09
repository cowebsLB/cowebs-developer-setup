[CmdletBinding()]
param(
    [string]$Version = '6.3.0-dev',
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$publishedVersions = @('6.0.0', '6.1.0', '6.2.0')
if ($Version -in $publishedVersions) {
    throw "Version $Version is already published and immutable. Check out its release tag to reproduce it, or build a new version."
}
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Version '$Version' is not a valid semantic version."
}
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot 'dist'
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-setup-build-{0}" -f [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $OutputDirectory ("cowebs-developer-setup-v{0}.zip" -f $Version)

try {
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'config') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'src\windows') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config\packages.json') -Destination (Join-Path $stagingRoot 'config\packages.json')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config\profiles.json') -Destination (Join-Path $stagingRoot 'config\profiles.json')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'src\windows\setup.ps1') -Destination (Join-Path $stagingRoot 'src\windows\setup.ps1')
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    [pscustomobject]@{ Version = $Version; Archive = $archivePath; SHA256 = $hash }
} finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
