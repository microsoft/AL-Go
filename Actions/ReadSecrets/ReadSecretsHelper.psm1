[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'GitHub Secrets come in as plain text')]
Param(
    [string] $_gitHubSecrets
)

$script:gitHubSecrets = $_gitHubSecrets | ConvertFrom-Json

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

function GetAzureCredentialsSecretName {
    $settings = $env:Settings | ConvertFrom-Json
    if ($settings.PSObject.Properties.Name -eq "AZURE_CREDENTIALSSecretName") {
        return $settings.AZURE_CREDENTIALSSecretName
    }
    else {
        return "AZURE_CREDENTIALS"
    }
}

function GetAzureCredentials {
    $secretName = GetAzureCredentialsSecretName
    if ($script:gitHubSecrets.PSObject.Properties.Name -eq $secretName) {
        return $script:gitHubSecrets."$secretName"
    }
    return $null
}

function GetGithubSecret {
    param (
        [string] $secretName,
        [switch] $encrypted
    )
    $secretSplit = $secretName.Split('=')
    $envVar = $secretSplit[0]
    $secret = $envVar
    if ($secretSplit.Count -gt 1) {
        $secret = $secretSplit[1]
    }

    if ($script:gitHubSecrets.PSObject.Properties.Name -eq $secret) {
        $value = $script:githubSecrets."$secret"
        if ($value) {
            MaskValue -key $envVar -value $value
            if ($encrypted) {
                # Return encrypted string
                return (ConvertTo-SecureString -String $value -AsPlainText -Force | ConvertFrom-SecureString)
            }
            else {
                # Return decrypted string
                return $value
            }
        }
    }

    return $null
}

function GetKeyVaultCredentials {
    $creds = $null
    $jsonStr = GetAzureCredentials
    if ($jsonStr) {
        if ($jsonStr -contains "`n" -or $jsonStr -contains "`r") {
            throw "Secret for Azure KeyVault Connection ($(GetAzureCredentialsSecretName)) cannot contain line breaks, needs to be formatted as compressed JSON (no line breaks)"
        }
        try {
            $creds = $jsonStr | ConvertFrom-Json
            if ($creds.PSObject.Properties.Name -eq 'ClientSecret' -and $creds.ClientSecret) {
                # Mask ClientSecret
                MaskValue -key 'ClientSecret' -value $creds.ClientSecret
            }
            # Check thet $creds contains the needed properties
            $creds.ClientId | Out-Null
            $creds.TenantId | Out-Null
        }
        catch {
            throw "Secret for Azure KeyVault Connection ($(GetAzureCredentialsSecretName)) is wrongly formatted. Needs to be formatted as compressed JSON (no line breaks) and contain at least the properties: clientId, clientSecret, tenantId and subscriptionId."
        }
        $keyVaultNameExists = $creds.PSObject.Properties.Name -eq 'keyVaultName'
        $settings = $env:Settings | ConvertFrom-Json
        # If KeyVaultName is defined in settings, use that value
        if ($settings.keyVaultName) {
            if ($keyVaultNameExists) {
                $creds.keyVaultName = $settings.keyVaultName
            }
            else {
                $creds | Add-Member -MemberType NoteProperty -Name 'keyVaultName' -Value $settings.keyVaultName
            }
        }
        elseif (!($keyVaultNameExists)) {
            # If KeyVaultName is not defined - return null (i.e. do not use a KeyVault)
            $creds = $null
        }
    }
    if ($creds) {
        try {
            # check that we have access to get secrets from the keyvault by trying to get a dummy secret
            GetKeyVaultSecret -secretName 'algodummysecret' -keyVaultCredentials $creds -encrypted | Out-Null
        }
        catch {
            Write-Host "Unable to get secrets from Azure Key Vault. Error was $($_.Exception.Message). Using Github secrets instead."
            $creds = $null
        }
    }
    return $creds
}

function GetKeyVaultSecret {
    param (
        [string] $secretName,
        [PsCustomObject] $keyVaultCredentials,
        [switch] $encrypted
    )
    if ($null -eq $keyVaultCredentials) {
        return $null
    }

    ConnectAz -azureCredentials $keyVaultCredentials

    $secretSplit = $secretName.Split('=')
    $envVar = $secretSplit[0]
    $secret = $envVar
    if ($secretSplit.Count -gt 1) {
        $secret = $secretSplit[1]
    }
    if ($secret.Contains('_')) {
        # Secret name contains a '_', which is not allowed in Key Vault secret names
        return $null
    }

    $value = $null
    try {
        $keyVaultSecret = Get-AzKeyVaultSecret -VaultName $keyVaultCredentials.keyVaultName -Name $secret
    }
    catch {
        if ($keyVaultCredentials.PSObject.Properties.Name -eq 'ClientSecret') {
            throw "Error trying to get secrets from Azure Key Vault. Error was $($_.Exception.Message)"
        }
        else {
            throw "Error trying to get secrets from Azure Key Vault, maybe your Key Vault isn't setup for role based access control?. Error was $($_.Exception.Message)"
        }
    }
    if ($keyVaultSecret) {
        if ($encrypted) {
            # Return encrypted string
            $value = $keyVaultSecret.SecretValue | ConvertFrom-SecureString
        }
        else {
            # Return decrypted string
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyVaultSecret.SecretValue)
            $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [Runtime.InteropServices.Marshal]::FreeBSTR($bstr)
            MaskValue -key $envVar -value $value
        }
    }
    return $value
}

function GetSecret {
    param (
        [string] $secret,
        [PSCustomObject] $keyVaultCredentials,
        [switch] $encrypted
    )

    Write-Host "Trying to get the secret ($secret) from the github environment."
    $value = GetGithubSecret -secretName $secret -encrypted:$encrypted
    if ($value) {
        Write-Host "Secret ($secret) was retrieved from the github environment."
    }
    elseif ($keyVaultCredentials) {
        Write-Host "Trying to get the secret ($secret) from Key Vault ($($keyVaultCredentials.keyVaultName))."
        $value = GetKeyVaultSecret -secretName $secret -keyVaultCredentials $keyVaultCredentials -encrypted:$encrypted
        if ($value) {
            Write-Host "Secret ($secret) was retrieved from the Key Vault."
        }
    }
    else {
        Write-Host  "Could not find secret $secret in Github secrets or Azure Key Vault."
        $value = $null
    }
    return $value
}
