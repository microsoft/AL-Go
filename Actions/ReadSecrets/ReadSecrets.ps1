Param(
    [string] $settingsJson = '{"keyVaultName": ""}',
    [string] $keyVaultName = "",
    [string] $secrets = "",
    [bool] $updateSettingsWithValues = $false
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")
    Import-Module (Join-Path $PSScriptRoot ".\ReadSecretHelper.psm1")

    $outSecrets = [ordered]@{}
    if ($keyVaultName -eq "") {
        # use SettingsJson
        $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
        $outSettings = $settings

        $keyVaultName = $settings.KeyVaultName
        if ([string]::IsNullOrEmpty($keyVaultName) -and (IsKeyVaultSet)) {
            $credentialsJson = Get-AzKeyVaultCredentials
            if ($credentialsJson.PSObject.Properties.Name -eq "KeyVaultName") {
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
    }
    else {
        [System.Collections.ArrayList]$secretsCollection = @($secrets.Split(','))
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
                Write-Host "Secret $envVar successfully read from GitHub Secret $secret"
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
}
catch {
    OutputError -message $_.Exception.Message
    exit
}
