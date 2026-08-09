[CmdletBinding()]
param(
    [string]$PackagesPath,
    [string]$ProfilesPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $PackagesPath) { $PackagesPath = Join-Path $projectRoot 'config\packages.json' }
if (-not $ProfilesPath) { $ProfilesPath = Join-Path $projectRoot 'config\profiles.json' }

function Get-OptionalValue {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-StringArray {
    param($Object, [string]$Name)
    $value = Get-OptionalValue -Object $Object -Name $Name
    if ($null -eq $value) { return [string[]]@() }
    return [string[]]@($value | ForEach-Object { [string]$_ })
}

function Assert-UniqueIds {
    param([object[]]$Items, [string]$PropertyName, [string]$Label)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in $Items) {
        $id = [string](Get-OptionalValue -Object $item -Name $PropertyName)
        if (-not $id) { throw "$Label contains an item without '$PropertyName'." }
        if (-not $seen.Add($id)) { throw "$Label contains duplicate id '$id'." }
    }
    return $seen
}

function Assert-KnownIds {
    param([string[]]$Ids, $KnownIds, [string]$Context)
    foreach ($id in $Ids) {
        if (-not $KnownIds.Contains($id)) { throw "$Context references unknown id '$id'." }
    }
}

function Assert-OnlyProperties {
    param($Object, [string[]]$Allowed, [string]$Context)
    foreach ($property in @($Object.PSObject.Properties)) {
        if ($Allowed -notcontains [string]$property.Name) {
            throw "$Context contains unsupported field '$($property.Name)'."
        }
    }
}

function Assert-NonEmptyText {
    param($Value, [string]$Context)
    if (-not ($Value -is [string]) -or [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -match '[\x00-\x1F\x7F]') {
        throw "$Context must be non-empty text without control characters."
    }
}

function Assert-Estimate {
    param($Estimate, [string]$Context)
    if (-not $Estimate) { throw "$Context is missing estimate ranges." }
    Assert-OnlyProperties -Object $Estimate -Allowed @('downloadMbMin', 'downloadMbMax', 'installMinutesMin', 'installMinutesMax') -Context "$Context estimate"
    foreach ($name in @('downloadMbMin', 'downloadMbMax', 'installMinutesMin', 'installMinutesMax')) {
        $value = Get-OptionalValue -Object $Estimate -Name $name
        if ($null -eq $value -or [double]$value -lt 0) { throw "$Context estimate '$name' must be a non-negative number." }
    }
    if ([double]$Estimate.downloadMbMax -lt [double]$Estimate.downloadMbMin) { throw "$Context download estimate maximum is less than its minimum." }
    if ([double]$Estimate.installMinutesMax -lt [double]$Estimate.installMinutesMin) { throw "$Context time estimate maximum is less than its minimum." }
}

function Convert-InstallOptions {
    param([string]$Override, [string]$PackageId)
    if (-not $Override) { return [string[]]@() }
    if ($Override -match '["'']') {
        throw "Package '$PackageId' uses a quoted Winget override that requires explicit schema-v3 migration."
    }
    return [string[]]@($Override -split '\s+' | Where-Object { $_ })
}

function Convert-Estimate {
    param($Estimate)
    return [ordered]@{
        downloadMbMin = [double]$Estimate.downloadMbMin
        downloadMbMax = [double]$Estimate.downloadMbMax
        installMinutesMin = [double]$Estimate.installMinutesMin
        installMinutesMax = [double]$Estimate.installMinutesMax
    }
}

function Convert-UbuntuProvider {
    param($Mapping, [string]$PackageId)
    $context = "Package '$PackageId' Ubuntu mapping"
    Assert-OnlyProperties -Object $Mapping -Allowed @(
        'support', 'reason', 'condition', 'alternativeName',
        'manager', 'packageId', 'source', 'privilege', 'scope',
        'architectures', 'installOptions', 'estimate'
    ) -Context $context

    $support = [string](Get-OptionalValue -Object $Mapping -Name 'support')
    if (@('native', 'alternative', 'conditional', 'unsupported') -notcontains $support) {
        throw "$context support must be native, alternative, conditional, or unsupported."
    }
    if ($support -eq 'unsupported') {
        Assert-NonEmptyText -Value (Get-OptionalValue -Object $Mapping -Name 'reason') -Context "$context reason"
        foreach ($field in @('manager', 'packageId', 'source', 'privilege', 'scope', 'architectures', 'installOptions', 'estimate', 'condition', 'alternativeName')) {
            if ($Mapping.PSObject.Properties[$field]) { throw "$context marked unsupported must not define provider field '$field'." }
        }
        return $null
    }

    if ($Mapping.PSObject.Properties['reason']) { throw "$context supported mapping must not define a reason." }
    if ($support -eq 'alternative') {
        Assert-NonEmptyText -Value (Get-OptionalValue -Object $Mapping -Name 'alternativeName') -Context "$context alternativeName"
    } elseif ($Mapping.PSObject.Properties['alternativeName']) {
        throw "$context alternativeName is only valid for alternative support."
    }
    if ($support -eq 'conditional') {
        Assert-NonEmptyText -Value (Get-OptionalValue -Object $Mapping -Name 'condition') -Context "$context condition"
    } elseif ($Mapping.PSObject.Properties['condition']) {
        throw "$context condition is only valid for conditional support."
    }

    $manager = [string](Get-OptionalValue -Object $Mapping -Name 'manager')
    if (@('apt-get', 'snap', 'flatpak') -notcontains $manager) { throw "$context uses unsupported manager '$manager'." }
    $providerPackageId = Get-OptionalValue -Object $Mapping -Name 'packageId'
    Assert-NonEmptyText -Value $providerPackageId -Context "$context packageId"
    if ([string]$providerPackageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+:-]*$') { throw "$context packageId contains unsupported characters." }

    $privilege = [string](Get-OptionalValue -Object $Mapping -Name 'privilege')
    $scope = [string](Get-OptionalValue -Object $Mapping -Name 'scope')
    $source = Get-OptionalValue -Object $Mapping -Name 'source'
    if ($manager -in @('apt-get', 'snap')) {
        if ($source) { throw "$context $manager provider must not define a custom source." }
        if ($privilege -ne 'elevated' -or $scope -ne 'machine') { throw "$context $manager provider must use elevated machine scope." }
    } else {
        Assert-NonEmptyText -Value $source -Context "$context source"
        if ([string]$source -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "$context source contains unsupported characters." }
        if (-not (($privilege -eq 'user' -and $scope -eq 'user') -or ($privilege -eq 'elevated' -and $scope -eq 'machine'))) {
            throw "$context flatpak provider must use user/user or elevated/machine privilege and scope."
        }
    }

    $architecturesProperty = $Mapping.PSObject.Properties['architectures']
    if (-not $architecturesProperty -or $architecturesProperty.Value -is [string]) { throw "$context architectures must be a typed array." }
    $architecturesValue = $architecturesProperty.Value
    $architectures = @($architecturesValue | ForEach-Object { [string]$_ })
    if ($architectures.Count -eq 0 -or @($architectures | Sort-Object -Unique).Count -ne $architectures.Count) { throw "$context architectures must be a non-empty unique array." }
    foreach ($architecture in $architectures) {
        if (@('x86', 'x64', 'arm64') -notcontains $architecture) { throw "$context contains unsupported architecture '$architecture'." }
    }

    $installOptionsProperty = $Mapping.PSObject.Properties['installOptions']
    if (-not $installOptionsProperty -or $installOptionsProperty.Value -is [string]) { throw "$context installOptions must be a typed array." }
    $installOptionsValue = $installOptionsProperty.Value
    $installOptions = @($installOptionsValue | ForEach-Object { [string]$_ })
    foreach ($option in $installOptions) { Assert-NonEmptyText -Value $option -Context "$context install option" }
    Assert-Estimate -Estimate (Get-OptionalValue -Object $Mapping -Name 'estimate') -Context $context

    $provider = [ordered]@{
        manager = $manager
        packageId = [string]$providerPackageId
    }
    if ($source) { $provider.source = [string]$source }
    $provider.privilege = $privilege
    $provider.scope = $scope
    $provider.architectures = $architectures
    $provider.detection = [ordered]@{ type = 'manager-native' }
    $provider.installOptions = $installOptions
    $provider.estimate = Convert-Estimate -Estimate $Mapping.estimate
    return [pscustomobject]$provider
}

function Write-DeterministicJson {
    param($Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 20
    $json = $json -replace "`r?`n", "`n"
    [IO.File]::WriteAllText($Path, ($json + "`n"), [Text.UTF8Encoding]::new($false))
}

$packageCatalogV2 = Get-Content -LiteralPath $PackagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profileCatalogV2 = Get-Content -LiteralPath $ProfilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($packageCatalogV2.schemaVersion -ne 2) { throw 'Package catalog schema version 2 is required.' }
if ($profileCatalogV2.schemaVersion -ne 2) { throw 'Profile catalog schema version 2 is required.' }

$packageItemsV2 = @($packageCatalogV2.packages)
$knownPackages = Assert-UniqueIds -Items $packageItemsV2 -PropertyName 'key' -Label 'Package catalog'
foreach ($package in $packageItemsV2) {
    $packageId = [string]$package.key
    $dependencies = @(Get-StringArray -Object $package -Name 'requires')
    $conflicts = @(Get-StringArray -Object $package -Name 'conflictsWith')
    Assert-KnownIds -Ids $dependencies -KnownIds $knownPackages -Context "Package '$packageId' dependencies"
    Assert-KnownIds -Ids $conflicts -KnownIds $knownPackages -Context "Package '$packageId' conflicts"
    foreach ($conflictId in $conflicts) {
        $other = $packageItemsV2 | Where-Object { $_.key -eq $conflictId } | Select-Object -First 1
        if (@(Get-StringArray -Object $other -Name 'conflictsWith') -notcontains $packageId) {
            throw "Package conflict '$packageId' -> '$conflictId' is not symmetric."
        }
    }
}

$estimatePolicy = Get-OptionalValue -Object $packageCatalogV2 -Name 'windowsEstimatePolicy'
if (-not $estimatePolicy) { throw 'Package catalog is missing windowsEstimatePolicy.' }
$packagesV3 = New-Object System.Collections.Generic.List[object]
foreach ($package in $packageItemsV2) {
    $packageId = [string]$package.key
    if ([string]$package.installStrategy -ne 'winget') {
        throw "Package '$packageId' uses unsupported v2 strategy '$($package.installStrategy)'."
    }
    $windows = Get-OptionalValue -Object $package.platforms -Name 'windows'
    if (-not $windows -or -not $windows.wingetId) { throw "Package '$packageId' has no Windows Winget mapping." }

    $conditions = Get-OptionalValue -Object $package -Name 'conditions'
    $overrideProperty = $estimatePolicy.overrides.PSObject.Properties[$packageId]
    if ($overrideProperty) {
        $estimateV2 = $overrideProperty.Value
    } elseif ($conditions -and (Get-OptionalValue -Object $conditions -Name 'diskHeavy')) {
        $estimateV2 = $estimatePolicy.diskHeavy
    } else {
        $estimateV2 = $estimatePolicy.default
    }

    $provider = [ordered]@{
        manager = 'winget'
        packageId = [string]$windows.wingetId
        source = 'winget'
        privilege = 'elevated'
        scope = 'auto'
        detection = [ordered]@{ type = 'manager-native' }
        installOptions = @(Convert-InstallOptions -Override ([string](Get-OptionalValue -Object $windows -Name 'wingetOverride')) -PackageId $packageId)
        estimate = Convert-Estimate -Estimate $estimateV2
    }

    $providers = [ordered]@{ windows = @($provider) }
    $ubuntu = Get-OptionalValue -Object $package.platforms -Name 'ubuntu'
    if ($ubuntu) {
        $ubuntuProvider = Convert-UbuntuProvider -Mapping $ubuntu -PackageId $packageId
        if ($null -ne $ubuntuProvider) { $providers.ubuntu = @($ubuntuProvider) }
    }

    $packageV3 = [ordered]@{
        id = $packageId
        name = [string]$package.name
        description = [string]$package.description
        tier = [string]$package.tier
        categories = @(Get-StringArray -Object $package -Name 'categories')
        license = [string]$package.license
        dependencies = @(Get-StringArray -Object $package -Name 'requires')
        conflicts = @(Get-StringArray -Object $package -Name 'conflictsWith')
        configurationIntents = @()
        providers = $providers
    }
    $configurationIntent = [string](Get-OptionalValue -Object $package -Name 'configure')
    if ($configurationIntent) { $packageV3.configurationIntents = @($configurationIntent) }
    if ($conditions) {
        $conditionsV3 = [ordered]@{}
        foreach ($conditionName in @('diskHeavy', 'restartMayBeRequired', 'authorizedLabOnly', 'hardwareRecommended')) {
            $conditionProperty = $conditions.PSObject.Properties[$conditionName]
            if ($conditionProperty) { $conditionsV3[$conditionName] = $conditionProperty.Value }
        }
        if ($conditionsV3.Count -gt 0) { $packageV3.conditions = $conditionsV3 }
    }
    $packagesV3.Add([pscustomobject]$packageV3)
}

$packProperties = @($profileCatalogV2.packs.PSObject.Properties)
$profileProperties = @($profileCatalogV2.profiles.PSObject.Properties)
$knownPacks = New-Object 'System.Collections.Generic.HashSet[string]'
$knownProfiles = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($property in $packProperties) {
    if (-not $knownPacks.Add([string]$property.Name)) { throw "Duplicate pack '$($property.Name)'." }
    Assert-KnownIds -Ids @(Get-StringArray -Object $property.Value -Name 'packages') -KnownIds $knownPackages -Context "Pack '$($property.Name)'"
}
foreach ($property in $profileProperties) {
    if (-not $knownProfiles.Add([string]$property.Name)) { throw "Duplicate profile '$($property.Name)'." }
}
Assert-KnownIds -Ids @($profileCatalogV2.corePackages | ForEach-Object { [string]$_ }) -KnownIds $knownPackages -Context 'Core package list'

function Assert-ProfileGraph {
    param([string]$ProfileId, [string[]]$Stack)
    if ($Stack -contains $ProfileId) { throw "Profile inheritance cycle: $($Stack -join ' -> ') -> $ProfileId" }
    $property = $profileCatalogV2.profiles.PSObject.Properties[$ProfileId]
    if (-not $property) { throw "Unknown profile '$ProfileId'." }
    $profile = $property.Value
    Assert-KnownIds -Ids @(Get-StringArray -Object $profile -Name 'packages') -KnownIds $knownPackages -Context "Profile '$ProfileId' packages"
    Assert-KnownIds -Ids @(Get-StringArray -Object $profile -Name 'recommendedPacks') -KnownIds $knownPacks -Context "Profile '$ProfileId' recommended packs"
    Assert-KnownIds -Ids @(Get-StringArray -Object $profile -Name 'optionalPacks') -KnownIds $knownPacks -Context "Profile '$ProfileId' optional packs"
    foreach ($parent in @(Get-StringArray -Object $profile -Name 'extends')) {
        if (-not $knownProfiles.Contains($parent)) { throw "Profile '$ProfileId' extends unknown profile '$parent'." }
        Assert-ProfileGraph -ProfileId $parent -Stack (@($Stack) + $ProfileId)
    }
}
foreach ($profileProperty in $profileProperties) { Assert-ProfileGraph -ProfileId $profileProperty.Name -Stack @() }

$packsV3 = New-Object System.Collections.Generic.List[object]
foreach ($property in $packProperties) {
    $packsV3.Add([pscustomobject][ordered]@{
        id = [string]$property.Name
        name = [string]$property.Value.name
        packageIds = @(Get-StringArray -Object $property.Value -Name 'packages')
    })
}
$profilesV3 = New-Object System.Collections.Generic.List[object]
foreach ($property in $profileProperties) {
    $profilesV3.Add([pscustomobject][ordered]@{
        id = [string]$property.Name
        name = [string]$property.Value.name
        extends = @(Get-StringArray -Object $property.Value -Name 'extends')
        packageIds = @(Get-StringArray -Object $property.Value -Name 'packages')
        recommendedPackIds = @(Get-StringArray -Object $property.Value -Name 'recommendedPacks')
        optionalPackIds = @(Get-StringArray -Object $property.Value -Name 'optionalPacks')
    })
}

$packageCatalogV3 = [ordered]@{
    schemaVersion = 3
    packages = $packagesV3.ToArray()
}
$profileCatalogV3 = [ordered]@{
    schemaVersion = 3
    corePackageIds = @($profileCatalogV2.corePackages | ForEach-Object { [string]$_ })
    packs = $packsV3.ToArray()
    profiles = $profilesV3.ToArray()
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
$packageOutputPath = Join-Path $resolvedOutput 'package-catalog.v3.json'
$profileOutputPath = Join-Path $resolvedOutput 'profile-catalog.v3.json'
Write-DeterministicJson -Value $packageCatalogV3 -Path $packageOutputPath
Write-DeterministicJson -Value $profileCatalogV3 -Path $profileOutputPath

[pscustomobject]@{
    PackageCatalog = $packageOutputPath
    ProfileCatalog = $profileOutputPath
    PackageCount = $packagesV3.Count
    PackCount = $packsV3.Count
    ProfileCount = $profilesV3.Count
}
