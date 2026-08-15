[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$DebianPackage,
    [Parameter(Mandatory)][string]$RpmPackage,
    [Parameter(Mandatory)][string]$ReleaseBaseUrl,
    [Parameter(Mandatory)][string]$CertificateIdentity
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+-rc\.\d+$') { throw 'Signed preview versions must use N.N.N-rc.N.' }
if ($ReleaseBaseUrl -notmatch '^https://github\.com/cowebsLB/cowebs-developer-setup/releases/download/v') { throw 'ReleaseBaseUrl must target the immutable COWebs GitHub release tag.' }
if ($CertificateIdentity -notmatch '^https://github\.com/cowebsLB/cowebs-developer-setup/\.github/workflows/[^@]+@refs/tags/v') { throw 'CertificateIdentity must bind the release workflow to an immutable tag.' }

function Write-Utf8Json {
    param($Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 30
    $json = $json -replace "`r?`n", "`n"
    [IO.File]::WriteAllText($Path, ($json + "`n"), [Text.UTF8Encoding]::new($false))
}

function Get-Record {
    param([string]$Path, [string]$Platform, [string]$Architecture, [string]$MinimumEnvironment)
    $name = Split-Path -Leaf $Path
    return [pscustomobject][ordered]@{
        name = $name
        platform = $Platform
        architecture = $Architecture
        url = "$($ReleaseBaseUrl.TrimEnd('/'))/$name"
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        sizeBytes = (Get-Item -LiteralPath $Path).Length
        minimumEnvironment = $MinimumEnvironment
        signature = "$($ReleaseBaseUrl.TrimEnd('/'))/$name.sigstore.json"
        certificateIdentity = $CertificateIdentity
    }
}

$manifestPath = Join-Path $OutputDirectory 'release-manifest-v1.json'
$checksumsPath = Join-Path $OutputDirectory 'SHA256SUMS'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Base release manifest is missing.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -ne $Version) { throw 'Base release manifest version does not match finalizer version.' }

$debDestination = Join-Path $OutputDirectory (Split-Path -Leaf $DebianPackage)
$rpmDestination = Join-Path $OutputDirectory (Split-Path -Leaf $RpmPackage)
Copy-Item -LiteralPath $DebianPackage -Destination $debDestination -Force
Copy-Item -LiteralPath $RpmPackage -Destination $rpmDestination -Force

$records = [Collections.Generic.List[object]]::new()
foreach ($artifact in @($manifest.artifacts)) {
    if ($artifact.name -in @((Split-Path -Leaf $DebianPackage), (Split-Path -Leaf $RpmPackage))) { continue }
    $path = Join-Path $OutputDirectory $artifact.name
    if (-not (Test-Path -LiteralPath $path)) { throw "Manifest artifact '$($artifact.name)' is missing." }
    $records.Add((Get-Record -Path $path -Platform $artifact.platform -Architecture $artifact.architecture -MinimumEnvironment $artifact.minimumEnvironment))
}
$records.Add((Get-Record -Path $debDestination -Platform 'linux' -Architecture 'x64' -MinimumEnvironment 'Ubuntu 24.04 x64 with dpkg'))
$records.Add((Get-Record -Path $rpmDestination -Platform 'linux' -Architecture 'x64' -MinimumEnvironment 'Fedora 43 or 44 x64 with DNF/RPM'))

$sbomRecord = $records | Where-Object { $_.name -eq "cowebs-$Version.spdx.json" } | Select-Object -First 1
$checksumRecord = $records | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
if (-not $sbomRecord -or -not $checksumRecord) { throw 'SBOM or checksum record is missing.' }

$sbomSubjects = @($records | Where-Object { $_.name -notin @($sbomRecord.name, $checksumRecord.name) })
$sbomFiles = @()
for ($index = 0; $index -lt $sbomSubjects.Count; $index++) {
    $subject = $sbomSubjects[$index]
    $sbomFiles += [ordered]@{
        fileName = $subject.name
        SPDXID = "SPDXRef-File-$($index + 1)"
        checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = $subject.sha256 })
        licenseConcluded = 'NOASSERTION'
        copyrightText = 'NOASSERTION'
    }
}
$sbom = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = "cowebs-$Version"
    documentNamespace = "https://cowebslb.com/spdx/cowebs/$Version/$($manifest.sourceCommit)"
    creationInfo = [ordered]@{
        created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        creators = @('Organization: COWebs.lb', 'Tool: scripts/finalize-cross-platform-release.ps1')
    }
    documentDescribes = @($sbomFiles | ForEach-Object { $_.SPDXID })
    files = $sbomFiles
}
$sbomPath = Join-Path $OutputDirectory $sbomRecord.name
Write-Utf8Json -Value $sbom -Path $sbomPath
$sbomRecord.sha256 = (Get-FileHash -LiteralPath $sbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sbomRecord.sizeBytes = (Get-Item -LiteralPath $sbomPath).Length

$checksumSubjects = @($records | Where-Object { $_.name -ne 'SHA256SUMS' } | Sort-Object name)
$checksumLines = @($checksumSubjects | ForEach-Object { "$($_.sha256)  $($_.name)" })
[IO.File]::WriteAllText($checksumsPath, (($checksumLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$checksumRecord.sha256 = (Get-FileHash -LiteralPath $checksumsPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumRecord.sizeBytes = (Get-Item -LiteralPath $checksumsPath).Length

$manifest.publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$manifest.artifacts = @($records | Sort-Object name)
Write-Utf8Json -Value $manifest -Path $manifestPath

[pscustomobject]@{
    Version = $Version
    Manifest = $manifestPath
    Checksums = $checksumsPath
    ArtifactCount = $records.Count
    CertificateIdentity = $CertificateIdentity
}
