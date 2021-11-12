Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the Telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScope, 
    [Parameter(HelpMessage = "Specifies the event Id in the telemetry", Mandatory = $false)]
    [string] $telemetryEventId,
    [Parameter(HelpMessage = "Settings from template repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"keyVaultName": ""}',
    [Parameter(HelpMessage = "Comma separated list of Secrets to get", Mandatory = $true)]
    [string] $secrets = "",
    [Parameter(HelpMessage = "Specifies if the values of secrets should be updated", Mandatory = $false)]
    [bool] $updateSettingsWithValues = $false
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
$BcContainerHelperPath = DownloadAndImportBcContainerHelper 
import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)

$telemetryScope = CreateScope -eventId $telemetryEventId -parentTelemetryScope $parentTelemetryScope

try {
    Import-Module (Join-Path $PSScriptRoot ".\ReadSecretsHelper.psm1")

    $outSecrets = [ordered]@{}
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $outSettings = $settings
    $keyVaultName = $settings.KeyVaultName
    if ([string]::IsNullOrEmpty($keyVaultName) -and (IsKeyVaultSet)) {
        $credentialsJson = Get-KeyVaultCredentials | ConvertTo-HashTable
        $credentialsJson.Keys | ForEach-Object { MaskValueInLog -value $credentialsJson."$_" }
        if ($credentialsJson.ContainsKey("KeyVaultName")) {
            $keyVaultName = $credentialsJson.KeyVaultName
        }
    }
    [System.Collections.ArrayList]$secretsCollection = @()
    $secrets.Split(',') | ForEach-Object {
        $secret = $_
        $secretNameProperty = "$($secret)SecretName"
        if ($settings.containsKey($secretNameProperty)) {
            $secret = "$($secret)=$($settings."$secretNameProperty")"
        }
        $secretsCollection += $secret
    }

    @($secretsCollection) | ForEach-Object {
        $secretSplit = $_.Split('=')
        $envVar = $secretSplit[0]
        $secret = $envVar
        if ($secretSplit.Count -gt 1) {
            $secret = $secretSplit[1]
        }

        if ($secret) {
            $value = GetSecret -secret $secret -keyVaultName $keyVaultName
            if ($value) {
                Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$value"
                $outSecrets += @{ "$envVar" = $value }
                Write-Host "$envVar successfully read from secret $secret"
                $secretsCollection.Remove($_)
            }
        }
    }

    if ($updateSettingsWithValues) {
        $outSettings.appDependencyProbingPaths | 
        ForEach-Object {
            if ($($_.authTokenSecret)) {
                $_.authTokenSecret = GetSecret -secret $_.authTokenSecret -keyVaultName $keyVaultName
            }
        } 
    }


    if ($secretsCollection) {
        Write-Host "The following secrets was not found: $(($secretsCollection | ForEach-Object { 
        $secretSplit = @($_.Split('='))
        if ($secretSplit.Count -eq 1) {
            $secretSplit[0]
        }
        else {
            "$($secretSplit[0]) (Secret $($secretSplit[1]))"
        }
        $outSecrets += @{ ""$($secretSplit[0])"" = """" }
    }) -join ', ')"
    }

    $outSecretsJson = $outSecrets | ConvertTo-Json -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "RepoSecrets=$outSecretsJson"

    $outSettingsJson = $outSettings | ConvertTo-Json -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    exit
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
