$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-signed-release-{0}" -f [guid]::NewGuid().ToString('N'))
$version = '6.3.0-rc.1'
$baseUrl = "https://github.com/cowebsLB/cowebs-developer-setup/releases/download/v$version"
$identity = "https://github.com/cowebsLB/cowebs-developer-setup/.github/workflows/release-cross-platform-preview.yml@refs/tags/v$version"
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $names = @(
        "cowebs-$version-windows-x64.zip",
        "cowebs-$version-linux-x64.tar.gz",
        "cowebs-$version-linux-arm64.tar.gz",
        "cowebs-install-$version.sh",
        "cowebs-$version.spdx.json",
        'SHA256SUMS'
    )
    foreach ($name in $names) { [IO.File]::WriteAllText((Join-Path $tempRoot $name), "fixture $name`n", [Text.UTF8Encoding]::new($false)) }
    $artifacts = @($names | ForEach-Object {
        $path = Join-Path $tempRoot $_
        [ordered]@{
            name = $_; platform = 'portable'; architecture = 'any'; url = "$baseUrl/$_"
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            sizeBytes = (Get-Item -LiteralPath $path).Length; minimumEnvironment = 'fixture'
        }
    })
    $manifest = [ordered]@{
        schemaVersion = 1; version = $version; sourceCommit = '0123456789012345678901234567890123456789'
        publishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); artifacts = $artifacts
    }
    [IO.File]::WriteAllText((Join-Path $tempRoot 'release-manifest-v1.json'), (($manifest | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    $packageFixtures = Join-Path $tempRoot 'package-fixtures'
    New-Item -ItemType Directory -Path $packageFixtures -Force | Out-Null
    $deb = Join-Path $packageFixtures "cowebs_${version}_amd64.deb.fixture"
    $rpm = Join-Path $packageFixtures "cowebs-$version.x86_64.rpm.fixture"
    [IO.File]::WriteAllText($deb, 'deb fixture', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($rpm, 'rpm fixture', [Text.UTF8Encoding]::new($false))

    $result = & (Join-Path $projectRoot 'scripts\finalize-cross-platform-release.ps1') -Version $version -OutputDirectory $tempRoot -DebianPackage $deb -RpmPackage $rpm -ReleaseBaseUrl $baseUrl -CertificateIdentity $identity
    Assert-True ($result.ArtifactCount -eq 8) 'Signed finalizer must retain six base artifacts and add DEB/RPM.'
    $final = Get-Content -LiteralPath $result.Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($final.artifacts).Count -eq 8) 'Final manifest artifact count changed.'
    foreach ($artifact in @($final.artifacts)) {
        Assert-True ($artifact.signature -eq "$baseUrl/$($artifact.name).sigstore.json") "Signature URL mismatch for $($artifact.name)."
        Assert-True ($artifact.certificateIdentity -eq $identity) "Certificate identity mismatch for $($artifact.name)."
    }
    $checksums = Get-Content -LiteralPath $result.Checksums -Encoding UTF8
    Assert-True ($checksums.Count -eq 7 -and ($checksums -join "`n") -match '\.deb\.fixture' -and ($checksums -join "`n") -match '\.rpm\.fixture') 'Final checksums do not cover native packages.'
    $sbom = Get-Content -LiteralPath (Join-Path $tempRoot "cowebs-$version.spdx.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ((@($sbom.files).fileName -contains (Split-Path -Leaf $deb)) -and (@($sbom.files).fileName -contains (Split-Path -Leaf $rpm))) 'Final SBOM does not cover native packages.'
    Write-Host 'PASS: signed release finalization, native-package inventory, checksums, SBOM, and identity metadata.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
exit 0
