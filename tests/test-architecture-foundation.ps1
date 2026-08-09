$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $projectRoot 'scripts\convert-catalog-v2-to-v3.ps1'
$packagesV2Path = Join-Path $projectRoot 'config\packages.json'
$profilesV2Path = Join-Path $projectRoot 'config\profiles.json'
$schemaRoot = Join-Path $projectRoot 'schema'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cowebs-architecture-foundation-{0}" -f [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-OptionalValue {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-Sha256 {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Write-Utf8Json {
    param($Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

try {
    $expectedSchemas = @(
        'package-catalog-v3.schema.json',
        'profile-catalog-v3.schema.json',
        'execution-plan-v1.schema.json',
        'execution-event-v1.schema.json',
        'release-manifest-v1.schema.json'
    )
    foreach ($schemaName in $expectedSchemas) {
        $schemaPath = Join-Path $schemaRoot $schemaName
        Assert-True (Test-Path -LiteralPath $schemaPath) "Missing schema '$schemaName'."
        $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($schema.'$schema' -eq 'https://json-schema.org/draft/2020-12/schema') "Schema '$schemaName' must use JSON Schema draft 2020-12."
        Assert-True ([bool]$schema.'$id') "Schema '$schemaName' has no stable id."
        Assert-True ($schema.additionalProperties -eq $false) "Schema '$schemaName' must reject unknown root fields."
    }

    foreach ($adrName in @(
        'README.md',
        '0001-cross-platform-go-core.md',
        '0002-least-privilege-broker.md',
        '0003-provider-aware-schema-v3.md',
        '0004-structured-execution-journal.md'
    )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "docs\adr\$adrName")) "Missing architecture decision record '$adrName'."
    }

    $packageSchemaText = Get-Content -LiteralPath (Join-Path $schemaRoot 'package-catalog-v3.schema.json') -Raw -Encoding UTF8
    $planSchemaText = Get-Content -LiteralPath (Join-Path $schemaRoot 'execution-plan-v1.schema.json') -Raw -Encoding UTF8
    Assert-True ($packageSchemaText -match '"installOptions"') 'Package schema must model installer options as typed tokens.'
    Assert-True ($packageSchemaText -match '"privilege"') 'Package schema must model privilege explicitly.'
    Assert-True ($planSchemaText -notmatch '"(?:command|shell)"') 'Execution plans must not accept arbitrary command or shell fields.'
    Assert-True ($planSchemaText -match '"then"\s*:\s*\{\s*"required"\s*:\s*\["manager",\s*"packageId"\]') 'Detect/install operations must require a typed provider mapping.'
    Assert-True ($planSchemaText -match '"then"\s*:\s*\{\s*"required"\s*:\s*\["configurationIntent"\]') 'Configure operations must require a configuration intent.'

    $outputOne = Join-Path $tempRoot 'one'
    $outputTwo = Join-Path $tempRoot 'two'
    $resultOne = & $compilerPath -OutputDirectory $outputOne
    $resultTwo = & $compilerPath -OutputDirectory $outputTwo
    Assert-True ($resultOne.PackageCount -eq 86) 'Compiler must preserve all 86 packages.'
    Assert-True ($resultOne.PackCount -eq 34) 'Compiler must preserve all 34 packs.'
    Assert-True ($resultOne.ProfileCount -eq 9) 'Compiler must preserve all nine profiles.'
    Assert-True ((Get-Sha256 $resultOne.PackageCatalog) -eq (Get-Sha256 $resultTwo.PackageCatalog)) 'Package catalog compilation is not deterministic.'
    Assert-True ((Get-Sha256 $resultOne.ProfileCatalog) -eq (Get-Sha256 $resultTwo.ProfileCatalog)) 'Profile catalog compilation is not deterministic.'

    $packagesV2 = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $profilesV2 = Get-Content -LiteralPath $profilesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $packagesV3 = Get-Content -LiteralPath $resultOne.PackageCatalog -Raw -Encoding UTF8 | ConvertFrom-Json
    $profilesV3 = Get-Content -LiteralPath $resultOne.ProfileCatalog -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($packagesV3.schemaVersion -eq 3) 'Compiled package schema version must be 3.'
    Assert-True ($profilesV3.schemaVersion -eq 3) 'Compiled profile schema version must be 3.'

    $compiledPackageIds = @($packagesV3.packages | ForEach-Object { $_.id })
    Assert-True (($compiledPackageIds | Sort-Object -Unique).Count -eq 86) 'Compiled package ids must be unique.'
    foreach ($sourcePackage in @($packagesV2.packages)) {
        $compiled = $packagesV3.packages | Where-Object { $_.id -eq $sourcePackage.key } | Select-Object -First 1
        Assert-True ($null -ne $compiled) "Compiled catalog lost package '$($sourcePackage.key)'."
        Assert-True ($compiled.name -eq $sourcePackage.name) "Package '$($sourcePackage.key)' changed display name."
        Assert-True ($compiled.tier -eq $sourcePackage.tier) "Package '$($sourcePackage.key)' changed tier."
        Assert-True (($compiled.dependencies -join ',') -eq (@(Get-OptionalValue $sourcePackage 'requires') -join ',')) "Package '$($sourcePackage.key)' changed dependencies."
        Assert-True (($compiled.conflicts -join ',') -eq (@(Get-OptionalValue $sourcePackage 'conflictsWith') -join ',')) "Package '$($sourcePackage.key)' changed conflicts."
        $expectedIntent = [string](Get-OptionalValue $sourcePackage 'configure')
        Assert-True (($compiled.configurationIntents -join ',') -eq $expectedIntent) "Package '$($sourcePackage.key)' changed configuration intent."
        $provider = @($compiled.providers.windows)[0]
        Assert-True ($provider.manager -eq 'winget') "Package '$($sourcePackage.key)' changed provider manager."
        Assert-True ($provider.packageId -eq $sourcePackage.platforms.windows.wingetId) "Package '$($sourcePackage.key)' changed Winget id."
        Assert-True ($provider.source -eq 'winget') "Package '$($sourcePackage.key)' changed Winget source."
        Assert-True ($provider.privilege -eq 'elevated' -and $provider.scope -eq 'auto') "Package '$($sourcePackage.key)' must preserve current elevated runtime behavior."
        Assert-True ($provider.detection.type -eq 'manager-native') "Package '$($sourcePackage.key)' must use manager-native detection."
        $override = [string](Get-OptionalValue $sourcePackage.platforms.windows 'wingetOverride')
        $expectedOptions = if ($override) { @($override -split '\s+' | Where-Object { $_ }) } else { @() }
        Assert-True (($provider.installOptions -join '|') -eq ($expectedOptions -join '|')) "Package '$($sourcePackage.key)' changed installer options."
        Assert-True ($provider.estimate.downloadMbMax -ge $provider.estimate.downloadMbMin) "Package '$($sourcePackage.key)' has an invalid download estimate."
        Assert-True ($provider.estimate.installMinutesMax -ge $provider.estimate.installMinutesMin) "Package '$($sourcePackage.key)' has an invalid time estimate."
        $sourceConditions = Get-OptionalValue $sourcePackage 'conditions'
        if ($sourceConditions) {
            foreach ($conditionName in @('diskHeavy', 'restartMayBeRequired', 'authorizedLabOnly', 'hardwareRecommended')) {
                $sourceCondition = $sourceConditions.PSObject.Properties[$conditionName]
                if ($sourceCondition) {
                    Assert-True ($compiled.conditions.PSObject.Properties[$conditionName].Value -eq $sourceCondition.Value) "Package '$($sourcePackage.key)' changed condition '$conditionName'."
                }
            }
        } else {
            Assert-True ($null -eq (Get-OptionalValue $compiled 'conditions')) "Package '$($sourcePackage.key)' gained unexpected conditions."
        }
    }

    Assert-True (($profilesV3.corePackageIds -join ',') -eq ($profilesV2.corePackages -join ',')) 'Core package order changed during compilation.'
    foreach ($sourcePackProperty in @($profilesV2.packs.PSObject.Properties)) {
        $compiled = $profilesV3.packs | Where-Object { $_.id -eq $sourcePackProperty.Name } | Select-Object -First 1
        Assert-True ($null -ne $compiled) "Compiled catalog lost pack '$($sourcePackProperty.Name)'."
        Assert-True (($compiled.packageIds -join ',') -eq ($sourcePackProperty.Value.packages -join ',')) "Pack '$($sourcePackProperty.Name)' changed package order."
    }
    foreach ($sourceProfileProperty in @($profilesV2.profiles.PSObject.Properties)) {
        $compiled = $profilesV3.profiles | Where-Object { $_.id -eq $sourceProfileProperty.Name } | Select-Object -First 1
        $source = $sourceProfileProperty.Value
        Assert-True ($null -ne $compiled) "Compiled catalog lost profile '$($sourceProfileProperty.Name)'."
        Assert-True (($compiled.extends -join ',') -eq (@(Get-OptionalValue $source 'extends') -join ',')) "Profile '$($sourceProfileProperty.Name)' changed inheritance."
        Assert-True (($compiled.packageIds -join ',') -eq ($source.packages -join ',')) "Profile '$($sourceProfileProperty.Name)' changed packages."
        Assert-True (($compiled.recommendedPackIds -join ',') -eq ($source.recommendedPacks -join ',')) "Profile '$($sourceProfileProperty.Name)' changed recommended packs."
        Assert-True (($compiled.optionalPackIds -join ',') -eq ($source.optionalPacks -join ',')) "Profile '$($sourceProfileProperty.Name)' changed optional packs."
    }

    $invalidPackages = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $invalidPackages.packages[0] | Add-Member -NotePropertyName requires -NotePropertyValue @('missing-package') -Force
    $invalidPackagesPath = Join-Path $tempRoot 'invalid-packages.json'
    Write-Utf8Json -Value $invalidPackages -Path $invalidPackagesPath
    $unknownReferenceRejected = $false
    try { & $compilerPath -PackagesPath $invalidPackagesPath -ProfilesPath $profilesV2Path -OutputDirectory (Join-Path $tempRoot 'invalid-output') | Out-Null }
    catch { $unknownReferenceRejected = $_.Exception.Message -match 'unknown id' }
    Assert-True $unknownReferenceRejected 'Compiler must reject unknown package references.'

    $quotedOverrideCatalog = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $quotedOverridePackage = $quotedOverrideCatalog.packages | Where-Object { $_.key -eq 'visual-studio-game' } | Select-Object -First 1
    $quotedOverridePackage.platforms.windows.wingetOverride = '--add "quoted workload"'
    $quotedOverridePath = Join-Path $tempRoot 'quoted-override.json'
    Write-Utf8Json -Value $quotedOverrideCatalog -Path $quotedOverridePath
    $quotedOverrideRejected = $false
    try { & $compilerPath -PackagesPath $quotedOverridePath -ProfilesPath $profilesV2Path -OutputDirectory (Join-Path $tempRoot 'quoted-output') | Out-Null }
    catch { $quotedOverrideRejected = $_.Exception.Message -match 'requires explicit schema-v3 migration' }
    Assert-True $quotedOverrideRejected 'Compiler must reject ambiguous quoted legacy overrides.'

    $compiledText = Get-Content -LiteralPath $resultOne.PackageCatalog -Raw -Encoding UTF8
    Assert-True ($compiledText -notmatch 'wingetOverride|installStrategy') 'Compiled v3 catalog must not retain raw v2 execution fields.'
    Write-Host 'PASS: schema-v3 contracts and deterministic v2-to-v3 catalog compilation.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
