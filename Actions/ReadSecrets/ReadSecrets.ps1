Param(
    [string] $settingsJson = '{"keyVaultName": ""}',
    [string] $keyVaultName = "",
    [string] $secrets = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

if ($keyVaultName -eq "") {
    # use SettingsJson
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $keyVaultName = $settings.KeyVaultName
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

$gitHubSecrets = $env:Secrets | ConvertFrom-Json
$outSecrets = [ordered]@{}

try {
    @($secretsCollection) | ForEach-Object {
        $secretSplit = $_.Split('=')
        $envVar = $secretSplit[0]
        $secret = $envVar
        if ($secretSplit.Count -gt 1) {
            $secret = $secretSplit[1]
        }
        if ($gitHubSecrets.PSObject.Properties.Name -eq $secret) {
            $value = $githubSecrets."$secret"
            if ($value) {
                MaskValueInLog -value $value
                Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$value"
                $outSecrets += @{ "$envVar" = $value }
                Write-Host "Secret $envVar successfully read from GitHub Secret $secret"
                $secretsCollection.Remove($_)
            }
        }
    }
}
catch {
    OutputError -message "Error reading from GitHub Secrets. Error was $($_.Exception.Message)"
}

if ($secretsCollection) {
    if ($gitHubSecrets.PSObject.Properties.Name -eq "AZURE_CREDENTIALS") {
        # use KeyVault for Secrets
        try {
            $credentials = $gitHuBSecrets.AZURE_CREDENTIALS | ConvertFrom-Json
            $clientId = $credentials.clientId
            $clientSecret = $credentials.clientSecret
            $subscriptionId = $credentials.subscriptionId
            $tenantId = $credentials.tenantId
            if ($keyVaultName -eq "" -and ($credentials.PSObject.Properties.Name -eq "KeyVaultName")) {
                $keyVaultName = $credentials.KeyVaultName
            }
        }
        catch {
            OutputError -message "AZURE_CREDENTIALS are wrongly formatted."
            Exit
        }
    }
    elseif ($keyVaultName -ne "") {
        OutputError -message "AZURE_CREDENTIALS are missing. In order to use a Keyvault, please add an AZURE_CREDENTIALS secret like explained here: https://docs.microsoft.com/en-us/azure/developer/github/connect-from-azure"
        Exit
    }

    if ($keyVaultName -ne "") {

        installModules -modules @('Az.KeyVault')
        try {
            Clear-AzContext -Scope Process
            Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
            $credential = New-Object PSCredential -argumentList $clientId, (ConvertTo-SecureString $clientSecret -AsPlainText -Force)
            Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $credential | Out-Null
            Set-AzContext -Subscription $subscriptionId -Tenant $tenantId | Out-Null
        }
        catch {
            OutputError -message "Error trying to authenticate to Azure using Az. Error was $($_.Exception.Message)"
            Exit
        }
    
        try {
            @($secretsCollection) | ForEach-Object {
                $secretSplit = $_.Split('=')
                $envVar = $secretSplit[0]
                $secret = $envVar
                if ($secretSplit.Count -gt 1) {
                    $secret = $secretSplit[1]
                }
    
                if ($secret) {
                    $keyVaultSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secret 
                    if ($keyVaultSecret) {
                        $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(([Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyVaultSecret.SecretValue)))
                        MaskValueInLog -value $value
                        MaskValueInLog -value $value.Replace('&','\u0026')
                        Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$value"
                        $outSecrets += @{ "$envVar" = $value }
                        Write-Host "Secret $envVar successfully read from KeyVault Secret $secret"
                        $secretsCollection.Remove($_)
                    }
                }
                else {
                    $secretsCollection.Remove($_)
                }
            }
        }
        catch {
            OutputError -message "Error reading from KeyVault. Error was $($_.Exception.Message)"
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
Add-Content -Path $env:GITHUB_ENV -Value "RepoSecrets=$OutSecretsJson"
