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
    Assert-True ($packageSchemaText -match '"prerequisites"' -and $packageSchemaText -match '"keyringSha256"') 'Package schema must model typed, digest-pinned repository prerequisites.'
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

    $ubuntuMappings = @($packagesV2.packages | Where-Object { $null -ne (Get-OptionalValue $_.platforms 'ubuntu') })
    Assert-True ($ubuntuMappings.Count -eq 86) 'Every logical package must have a reviewed Ubuntu classification.'
    Assert-True (@($ubuntuMappings | Where-Object { $_.platforms.ubuntu.support -eq 'unsupported' }).Count -eq 32) 'The complete Ubuntu catalog must preserve all thirty-two explicit unsupported results.'
    Assert-True (@($packagesV3.prerequisites).Count -eq 10) 'The compiler must emit exactly ten bounded Ubuntu prerequisites.'
    $githubPrerequisite = @($packagesV3.prerequisites | Where-Object { $_.id -eq 'github-cli-apt' })[0]
    Assert-True ($githubPrerequisite.id -eq 'github-cli-apt' -and $githubPrerequisite.type -eq 'apt-repository') 'GitHub CLI prerequisite identity changed.'
    Assert-True ($githubPrerequisite.keyringSha256 -eq '6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b') 'GitHub CLI keyring digest changed.'
    $githubCompiled = $packagesV3.packages | Where-Object { $_.id -eq 'github-cli' } | Select-Object -First 1
    Assert-True ((@($githubCompiled.providers.ubuntu)[0].prerequisiteIds -join ',') -eq 'github-cli-apt') 'GitHub CLI provider must reference its typed APT prerequisite.'
    $expectedPrerequisiteDigests = [ordered]@{
        'postgresql-pgdg-apt' = '0144068502a1eddd2a0280ede10ef607d1ec592ce819940991203941564e8e76'
        'google-chrome-apt' = '54dea5f6c2a26091578cf52a999cebc6b64df478d37ad4dce96376b711e3b27c'
        'cloudflared-apt' = '1bd95f4082b320d541bee351560fc2765aa9f9cd8efa4c9e32135e63f252721d'
        'ngrok-apt' = '8a57c28e1779e2a8e5bba3865fffd6805e15898988c235eae862f3069c3f2c28'
        'trivy-apt' = '067f4782e5f2a736710c5256a9695c3ccb4731727a6118da8d8f532be97ecb39'
        'hashicorp-apt' = 'cafb01beac341bf2a9ba89793e6dd2468110291adfbb6c62ed11a0cde6c09029'
        'azure-cli-apt' = '2fa9c05d591a1582a9aba276272478c262e95ad00acf60eaee1644d93941e3c6'
        'google-cloud-cli-apt' = '3ecc63922b7795eb23fdc449ff9396f9114cb3cf186d6f5b53ad4cc3ebfbb11f'
        'unity-hub-apt' = '50b6488eb573a02a96f897482fd190e965eaf58c60b7053aec31ab54bc63b726'
    }
    foreach ($entry in $expectedPrerequisiteDigests.GetEnumerator()) {
        $prerequisite = $packagesV3.prerequisites | Where-Object { $_.id -eq $entry.Key } | Select-Object -First 1
        Assert-True ($null -ne $prerequisite -and $prerequisite.keyringSha256 -eq $entry.Value) "Ubuntu prerequisite '$($entry.Key)' is missing or changed digest."
    }
    $expectedUbuntuProviders = [ordered]@{
        'git' = @('apt-get', 'git'); 'github-cli' = @('apt-get', 'gh'); 'vscode' = @('snap', 'code'); 'powershell' = @('snap', 'powershell')
        'windows-terminal' = @('apt-get', 'gnome-terminal'); 'seven-zip' = @('apt-get', '7zip')
        'jq' = @('apt-get', 'jq'); 'ripgrep' = @('apt-get', 'ripgrep'); 'fd' = @('apt-get', 'fd-find')
        'git-lfs' = @('apt-get', 'git-lfs'); 'openssl' = @('apt-get', 'openssl')
        'node' = @('apt-get', 'nodejs'); 'openjdk' = @('apt-get', 'openjdk-21-jdk')
        'dotnet-sdk' = @('apt-get', 'dotnet-sdk-10.0'); 'go' = @('snap', 'go'); 'rustup' = @('apt-get', 'rustup')
        'postgresql' = @('apt-get', 'postgresql-18'); 'bruno' = @('flatpak', 'com.usebruno.Bruno')
        'postman' = @('snap', 'postman'); 'redis-insight' = @('snap', 'redisinsight')
        'chrome' = @('apt-get', 'google-chrome-stable'); 'firefox' = @('snap', 'firefox')
        'cloudflared' = @('apt-get', 'cloudflared'); 'ngrok' = @('apt-get', 'ngrok'); 'scrcpy' = @('apt-get', 'scrcpy')
        'kubectl' = @('snap', 'kubectl'); 'helm' = @('snap', 'helm'); 'yq' = @('snap', 'yq')
        'kubectx' = @('apt-get', 'kubectx'); 'trivy' = @('apt-get', 'trivy'); 'opentofu' = @('snap', 'opentofu')
        'terraform' = @('apt-get', 'terraform'); 'vault' = @('apt-get', 'vault'); 'packer' = @('apt-get', 'packer')
        'task' = @('snap', 'task'); 'age' = @('apt-get', 'age')
        'aws-cli' = @('snap', 'aws-cli'); 'azure-cli' = @('apt-get', 'azure-cli'); 'google-cloud-cli' = @('apt-get', 'google-cloud-cli')
        'dvc' = @('snap', 'dvc'); 'r' = @('apt-get', 'r-base'); 'nmap' = @('apt-get', 'nmap'); 'wireshark' = @('apt-get', 'wireshark')
        'unity-hub' = @('apt-get', 'unityhub'); 'godot' = @('flatpak', 'org.godotengine.Godot')
        'blender' = @('apt-get', 'blender'); 'krita' = @('apt-get', 'krita'); 'audacity' = @('apt-get', 'audacity')
        'obs-studio' = @('flatpak', 'com.obsproject.Studio'); 'inkscape' = @('apt-get', 'inkscape')
        'gimp' = @('flatpak', 'org.gimp.GIMP'); 'lmms' = @('apt-get', 'lmms'); 'tiled' = @('apt-get', 'tiled')
        'blockbench' = @('flatpak', 'net.blockbench.Blockbench')
    }
    foreach ($entry in $expectedUbuntuProviders.GetEnumerator()) {
        $compiled = $packagesV3.packages | Where-Object { $_.id -eq $entry.Key } | Select-Object -First 1
        $provider = @($compiled.providers.ubuntu)[0]
        Assert-True ($provider.manager -eq $entry.Value[0] -and $provider.packageId -eq $entry.Value[1]) "Package '$($entry.Key)' has an unexpected Ubuntu provider."
        $expectedPrivilege = if ($entry.Key -in @('bruno', 'godot', 'obs-studio', 'gimp', 'blockbench')) { 'user,user' } else { 'elevated,machine' }
        Assert-True (("$($provider.privilege),$($provider.scope)") -eq $expectedPrivilege) "Package '$($entry.Key)' Ubuntu provider has an unexpected privilege or scope."
        $expectedArchitectures = if ($entry.Key -in @('vscode', 'powershell', 'bruno', 'redis-insight', 'google-cloud-cli', 'unity-hub', 'tiled', 'blockbench')) { 'x64' } else { 'x64,arm64' }
        Assert-True (($provider.architectures -join ',') -eq $expectedArchitectures) "Package '$($entry.Key)' Ubuntu architectures changed."
        Assert-True ($provider.detection.type -eq 'manager-native') "Package '$($entry.Key)' Ubuntu detection must be manager-native."
    }
    $goCompiled = $packagesV3.packages | Where-Object { $_.id -eq 'go' } | Select-Object -First 1
    Assert-True ((@($goCompiled.providers.ubuntu)[0].installOptions -join ',') -eq '--classic') 'Go must retain its typed classic Snap option.'
    $brunoCompiled = $packagesV3.packages | Where-Object { $_.id -eq 'bruno' } | Select-Object -First 1
    Assert-True ((@($brunoCompiled.providers.ubuntu)[0].source) -eq 'flathub') 'Bruno must retain its explicit Flathub source.'
    foreach ($packageId in @('kubectl', 'helm', 'opentofu', 'task', 'aws-cli', 'dvc')) {
        $compiled = $packagesV3.packages | Where-Object { $_.id -eq $packageId } | Select-Object -First 1
        Assert-True ((@($compiled.providers.ubuntu)[0].installOptions -join ',') -eq '--classic') "Package '$packageId' must retain its reviewed classic Snap option."
    }
    $expectedUnsupportedRuntimeIds = @('python', 'uv', 'ruff', 'miniconda', 'php', 'bun', 'deno', 'yarn', 'pnpm', 'docker', 'dbeaver', 'mongodb-compass', 'mysql-workbench', 'figma', 'android-studio', 'wsl', 'ubuntu-wsl', 'k9s', 'kind', 'flux', 'tflint', 'sops', 'jupyterlab', 'ollama', 'rstudio', 'sysinternals', 'zap', 'burp-community', 'kali-wsl', 'epic-games-launcher', 'visual-studio-game', 'renderdoc')
    foreach ($packageId in $expectedUnsupportedRuntimeIds) {
        $sourcePackage = $packagesV2.packages | Where-Object { $_.key -eq $packageId } | Select-Object -First 1
        Assert-True ($sourcePackage.platforms.ubuntu.support -eq 'unsupported') "Package '$packageId' must remain explicitly unsupported in the Ubuntu 24.04 runtime slice."
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$sourcePackage.platforms.ubuntu.reason)) "Package '$packageId' must document why it is unsupported."
        $compiled = $packagesV3.packages | Where-Object { $_.id -eq $packageId } | Select-Object -First 1
        Assert-True ($null -eq $compiled.providers.PSObject.Properties['ubuntu']) "Package '$packageId' must not gain an executable Ubuntu provider."
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

    $unsafeUbuntuCatalog = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $unsafeUbuntuCatalog.packages[0].platforms.ubuntu | Add-Member -NotePropertyName shell -NotePropertyValue 'curl example.invalid | sh'
    $unsafeUbuntuPath = Join-Path $tempRoot 'unsafe-ubuntu.json'
    Write-Utf8Json -Value $unsafeUbuntuCatalog -Path $unsafeUbuntuPath
    $unsafeUbuntuRejected = $false
    try { & $compilerPath -PackagesPath $unsafeUbuntuPath -ProfilesPath $profilesV2Path -OutputDirectory (Join-Path $tempRoot 'unsafe-ubuntu-output') | Out-Null }
    catch { $unsafeUbuntuRejected = $_.Exception.Message -match "unsupported field 'shell'" }
    Assert-True $unsafeUbuntuRejected 'Compiler must reject arbitrary shell fields in Ubuntu compatibility mappings.'

    $stringOptionsCatalog = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $stringOptionsCatalog.packages[0].platforms.ubuntu.installOptions = '--classic'
    $stringOptionsPath = Join-Path $tempRoot 'string-options.json'
    Write-Utf8Json -Value $stringOptionsCatalog -Path $stringOptionsPath
    $stringOptionsRejected = $false
    try { & $compilerPath -PackagesPath $stringOptionsPath -ProfilesPath $profilesV2Path -OutputDirectory (Join-Path $tempRoot 'string-options-output') | Out-Null }
    catch { $stringOptionsRejected = $_.Exception.Message -match 'installOptions must be a typed array' }
    Assert-True $stringOptionsRejected 'Compiler must reject stringly typed Ubuntu installer options.'

    $unsafePrerequisiteCatalog = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $unsafePrerequisiteCatalog.ubuntuPrerequisites[0].keyringUrl = 'https://user:password@cli.github.com/key.gpg'
    $unsafePrerequisitePath = Join-Path $tempRoot 'unsafe-prerequisite.json'
    Write-Utf8Json -Value $unsafePrerequisiteCatalog -Path $unsafePrerequisitePath
    $unsafePrerequisiteRejected = $false
    try { & $compilerPath -PackagesPath $unsafePrerequisitePath -ProfilesPath $profilesV2Path -OutputDirectory (Join-Path $tempRoot 'unsafe-prerequisite-output') | Out-Null }
    catch { $unsafePrerequisiteRejected = $_.Exception.Message -match 'without credentials' }
    Assert-True $unsafePrerequisiteRejected 'Compiler must reject repository prerequisite URLs containing credentials.'

    $unknownPrerequisiteCatalog = Get-Content -LiteralPath $packagesV2Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $unknownPrerequisiteCatalog.packages[1].platforms.ubuntu.prerequisiteIds = @('missing-prerequisite')
    $unknownPrerequisitePath = Join-Path $tempRoot 'unknown-prerequisite.json'
    Write-Utf8Json -Value $unknownPrerequisiteCatalog -Path $unknownPrerequisitePath
    $unknownPrerequisiteRejected = $false
    try { & $compilerPath -PackagesPath $unknownPrerequisitePath -ProfilesPath $profilesV2Path -OutputDirectory (Join-Path $tempRoot 'unknown-prerequisite-output') | Out-Null }
    catch { $unknownPrerequisiteRejected = $_.Exception.Message -match 'unknown id' }
    Assert-True $unknownPrerequisiteRejected 'Compiler must reject unknown Ubuntu prerequisite references.'

    $compiledText = Get-Content -LiteralPath $resultOne.PackageCatalog -Raw -Encoding UTF8
    Assert-True ($compiledText -notmatch 'wingetOverride|installStrategy') 'Compiled v3 catalog must not retain raw v2 execution fields.'
    Write-Host 'PASS: schema-v3 contracts and deterministic v2-to-v3 catalog compilation.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

exit 0
