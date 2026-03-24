# TRASER NewBcContainer Override Implementation
# Called from .AL-Go/NewBcContainer.ps1 thin wrapper in product repos.

Param(
    [hashtable]$parameters
)

$containerName = $parameters.ContainerName

$parameters["accept_insiderEula"] = $true
$parameters["TimeZoneId"] = (Get-TimeZone).Id
$parameters["accept_outdated"] = $true

if (-not $parameters.ContainsKey("includeTestToolkit")) {
    $parameters["includeTestToolkit"] = $true
    $parameters["includeTestLibrariesOnly"] = $true
}

if (-not $parameters.ContainsKey("additionalParameters")) {
    $parameters["additionalParameters"] = @()
}
$parameters["additionalParameters"] += @(
    "--env defaultTenantHasAllowAppDatabaseWrite=Y",
    "-e customNavSettings=ClientServicesMaxUploadSize=2000"
)

$bakFolder = $ENV:BAK_FOLDER
if ($bakFolder -and (Test-Path $bakFolder)) {
    Write-Host "Using BAK folder: $bakFolder"
    $parameters["bakFolder"] = $bakFolder
}

New-BcContainer @parameters

if (-not $parameters.filesOnly) {
    $traefikDomain = $ENV:TRAEFIK_DOMAIN
    if ($traefikDomain) {
        Write-Host "Configuring Traefik timeout settings for $containerName"
        Invoke-ScriptInBcContainer -containerName $containerName -usePwsh $false -scriptblock {
            Param($webServerInstance)
            Set-NAVWebServerInstanceConfiguration -WebServerInstance $webServerInstance -KeyName "SessionTimeout" -KeyValue "23:59:59"
            Set-NAVServerConfiguration $ServerInstance -KeyName "SqlConnectionIdleTimeout" -KeyValue "23:59:59" -ErrorAction Continue
            Set-NAVServerConfiguration $ServerInstance -KeyName "SqlCommandTimeout" -KeyValue "03:00:00" -ErrorAction Continue
            Install-WindowsFeature web-scripting-tools -ErrorAction SilentlyContinue
            Set-WebConfigurationProperty -filter /system.webserver/security/requestfiltering/requestLimits -name maxAllowedContentLength -value 2000000000
            Restart-NAVServerInstance $serverInstance
            while (Get-NavTenant $serverInstance | Where-Object { $_.State -eq "Mounting" }) {
                Start-Sleep -Seconds 1
            }
        } -argumentList $containerName
    }

    $forNAVServicePath = $ENV:FORNAV_SERVICE_PATH
    if ($forNAVServicePath -and (Test-Path $forNAVServicePath)) {
        Write-Host "Installing ForNAV Service from $forNAVServicePath"
        $forNAVContainerFolder = "C:\Run\ForNAV Service"
        try {
            Copy-FileToBcContainer -containerName $containerName -localPath $forNAVServicePath -containerPath ($forNAVContainerFolder + '\' + (Split-Path $forNAVServicePath -Leaf))
            $containerExe = $forNAVContainerFolder + '\' + (Split-Path $forNAVServicePath -Leaf)
            Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
                Param([string]$exePath)
                Start-Process -FilePath $exePath -ArgumentList '/COMPONENTS="deployment\reportservice"', '/VERYSILENT', '/NORESTART', '/SUPPRESSMESSAGEBOXES' -Wait
            } -ArgumentList $containerExe
        } catch {
            Write-Warning "ForNAV Service installation failed: $_"
        }
    }

    $fontsFolder = $ENV:CUSTOM_FONTS_PATH
    if ($fontsFolder -and (Test-Path $fontsFolder)) {
        Get-ChildItem -Path $fontsFolder -Filter "*.ttf" | ForEach-Object {
            Add-FontsToBcContainer -containerName $containerName -path $_.FullName
        }
    }

    Get-ChildItem -Path "c:\windows\fonts" -Filter "arial*.ttf" -ErrorAction SilentlyContinue | ForEach-Object {
        Add-FontsToBcContainer -containerName $containerName -path $_.FullName
    }
}

Write-Host "TRASER container setup complete for $containerName"
