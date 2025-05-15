$script:escchars = @(' ','!','\"','#','$','%','\u0026','\u0027','(',')','*','+',',','-','.','/','0','1','2','3','4','5','6','7','8','9',':',';','\u003c','=','\u003e','?','@','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','[','\\',']','^','_',[char]96,'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','{','|','}','~')

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

function MaskValue {
    Param(
        [string] $key,
        [string] $value
    )

    $value = $value.Trim()
    if ([String]::IsNullOrEmpty($value)) {
        return
    }

    Write-Host "Masking value for $key"
    $value.Split("`n") | ForEach-Object {
        Write-Host "::add-mask::$_"
    }

    $val2 = ""
    $value.ToCharArray() | ForEach-Object {
        $chint = [int]$_
        if ($chint -lt 32 -or $chint -gt 126 ) {
            $val2 += $_
        }
        else {
           $val2 += $script:escchars[$chint-32]
        }
    }

    if ($val2 -ne $value) {
        $val2.Split("`n") | ForEach-Object {
            Write-Host "::add-mask::$_"
        }
    }
    Write-Host "::add-mask::$([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value)))"
}

function GetKeyVaultCredentials {
    Param(
        [string] $jsonStr
    )

    $creds = $null
    if ($jsonStr) {
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
            throw "Secret for Azure KeyVault Connection is wrongly formatted. Needs to be formatted as compressed JSON (no line breaks) and contain at least the properties: clientId, clientSecret, tenantId and subscriptionId."
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
            MaskValue -key $envVar -value $value
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
