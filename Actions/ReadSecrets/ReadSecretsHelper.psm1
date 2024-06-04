[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'GitHub Secrets come in as plain text')]
Param(
    [string] $_gitHubSecrets
)

$script:gitHubSecrets = $_gitHubSecrets | ConvertFrom-Json
$script:keyvaultConnectionExists = $false
$script:isKeyvaultSet = $script:gitHubSecrets.PSObject.Properties.Name -eq "AZURE_CREDENTIALS"
$script:escchars = @(' ','!','\"','#','$','%','\u0026','\u0027','(',')','*','+',',','-','.','/','0','1','2','3','4','5','6','7','8','9',':',';','\u003c','=','\u003e','?','@','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','[','\\',']','^','_',[char]96,'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','{','|','}','~')

if ($PSVersionTable.PSVersion -lt [Version]"6.0.0") {
    $script:isWindows = $true
}

function IsKeyVaultSet {
    return $script:isKeyvaultSet
}

function MaskValue {
    Param(
        [string] $key,
        [string] $value
    )

    Write-Host "Masking value for $key"
    Write-Host "::add-mask::$value"

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
        Write-Host "::add-mask::$val2"
    }
    Write-Host "::add-mask::$([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value)))"
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
    if ($script:isKeyvaultSet) {
        $jsonStr = $script:gitHubSecrets.AZURE_CREDENTIALS
        if ($jsonStr -contains "`n" -or $jsonStr -contains "`r") {
            throw "Secret AZURE_CREDENTIALS cannot contain line breaks, needs to be formatted as compressed JSON (no line breaks)"
        }
        try {
            $creds = $jsonStr | ConvertFrom-Json
            if ($creds.ClientSecret) {
                # Mask ClientSecret
                MaskValue -key 'ClientSecret' -value $creds.ClientSecret
                $creds.ClientSecret = ConvertTo-SecureString $creds.ClientSecret -AsPlainText -Force
            }
            else {
                try {
                    Write-Host "Query ID_TOKEN from $ENV:ACTIONS_ID_TOKEN_REQUEST_URL"
                    $result = Invoke-RestMethod -Method GET -UseBasicParsing -Headers @{ "Authorization" = "bearer $ENV:ACTIONS_ID_TOKEN_REQUEST_TOKEN"; "Accept" = "application/vnd.github+json" } -Uri "$ENV:ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
                    $creds | Add-Member -MemberType NoteProperty -Name 'ClientAssertion' -Value $result.value
                }
                catch {
                    Write-Host "::WARNING::Unable to get ID_TOKEN, maybe id_token: write permissions are missing"
                }
            }
            # Check thet $creds contains the needed properties
            $creds.ClientId | Out-Null
            $creds.TenantId | Out-Null
            if ($creds.PSObject.Properties.Name -eq 'ErrorAction') {
                if (@('Error','Warning','None') -notcontains $creds.ErrorAction) {
                    throw "AZURE_CREDENTIALS.ErrorAction needs to be one of 'Error', 'Warning' or 'None'."
                }
            }
            else {
                $creds | Add-Member -MemberType NoteProperty -Name 'ErrorAction' -Value 'Warning'
            }
        }
        catch {
            throw "Secret AZURE_CREDENTIALS is wrongly formatted. Needs to be formatted as compressed JSON (no line breaks) and contain at least the properties: clientId, clientSecret, tenantId and subscriptionId."
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
    return $creds
}

function InstallKeyVaultModuleIfNeeded {
    if (Get-Module -Name 'Az.KeyVault') {
        # Already installed
        return
    }
    if ($isWindows) {
        # GitHub hosted Windows Runners have AZ PowerShell module saved in C:\Modules\az_*
        # Remove AzureRm modules from PSModulePath and add AZ modules
        if (Test-Path 'C:\Modules\az_*') {
            $azModulesPath = Get-ChildItem 'C:\Modules\az_*' | Where-Object { $_.PSIsContainer }
            if ($azModulesPath) {
              Write-Host "Adding AZ module path: $($azModulesPath.FullName)"
              $ENV:PSModulePath = "$($azModulesPath.FullName);$(("$ENV:PSModulePath".Split(';') | Where-Object { $_ -notlike 'C:\\Modules\Azure*' }) -join ';')"
            }
        }
    }
    else {
        # Linux runners have AZ PowerShell module saved in /usr/share/powershell/Modules/Az.*
    }
    $azKeyVaultModule = Get-Module -name 'Az.KeyVault' -ListAvailable | Select-Object -First 1
    if ($azKeyVaultModule) {
        Write-Host "Az.KeyVault Module is available in version $($azKeyVaultModule.Version)"
        Write-Host "Using Az.KeyVault version $($azKeyVaultModule.Version)"
    }
    else {
        $AzKeyVaultModule = Get-InstalledModule -Name 'Az.KeyVault' -ErrorAction SilentlyContinue
        if ($AzKeyVaultModule) {
            Write-Host "Az.KeyVault version $($AzKeyVaultModule.Version) is installed"
        }
        else {
            Write-Host "Installing and importing Az.KeyVault"
            Install-Module 'Az.KeyVault' -Force
        }
    }
    Import-Module  'Az.KeyVault' -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
}

function ConnectAzureKeyVault {
    param(
        [PsCustomObject] $keyVaultCredentials
    )
    try {
        Clear-AzContext -Scope Process
        Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        if ($keyVaultCredentials.PSObject.Properties.Name -eq 'ClientAssertion') {
            Connect-AzAccount -ApplicationId $keyVaultCredentials.ClientId -Tenant $keyVaultCredentials.TenantId -FederatedToken $keyVaultCredentials.ClientAssertion -WarningAction SilentlyContinue | Out-Null
        }
        else {
            $credential = New-Object PSCredential -argumentList $keyVaultCredentials.ClientId, $keyVaultCredentials.ClientSecret
            Connect-AzAccount -ServicePrincipal -Tenant $keyVaultCredentials.TenantId -Credential $credential -WarningAction SilentlyContinue | Out-Null
        }
        if ($keyVaultCredentials.PSObject.Properties.Name -eq 'SubScriptionId') {
            Set-AzContext -SubscriptionId $keyVaultCredentials.SubscriptionId -Tenant $keyVaultCredentials.TenantId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
        }
        $script:keyvaultConnectionExists = $true
        Write-Host "Successfully connected to Azure Key Vault."
    }
    catch {
        throw "Error trying to authenticate to Azure using Az. Error was $($_.Exception.Message)"
    }
}

function GetKeyVaultSecret {
    param (
        [string] $secretName,
        [PsCustomObject] $keyVaultCredentials,
        [switch] $encrypted
    )

    if (-not $script:isKeyvaultSet) {
        return $null
    }

    if (-not $script:keyvaultConnectionExists) {
        InstallKeyVaultModuleIfNeeded
        $message = ''
        try {
            ConnectAzureKeyVault -keyVaultCredentials $keyVaultCredentials
        }
        catch {
            $message = "Error trying to get secrets from Azure Key Vault. Error was $($_.Exception.Message)"
        }
        if (-not $message) {
            try {
                Get-AzKeyVaultSecret -VaultName $keyVaultCredentials.keyVaultName | ForEach-Object { $_.Name } | Out-Null
            }
            catch {
                if ($keyVaultCredentials.PSObject.Properties.Name -eq 'ClientAssertion') {
                    $message = "Error trying to get secrets from Azure Key Vault, maybe your Key Vault isn't setup for role based access control?. Error was $($_.Exception.Message)"
                }
                else {
                    $message = "Error trying to get secrets from Azure Key Vault. Error was $($_.Exception.Message)"
                }
            }
        }
        if ($message) {
            $script:isKeyvaultSet = $false
            switch($keyVaultCredentials.ErrorAction) {
                'Error' {
                    throw $message
                }
                'None' {
                    Write-Host $message
                    return $null
                }
                default {
                    Write-Host "::WARNING::$message"
                    return $null
                }
            }
        }
    }

    $secretSplit = $secretName.Split('=')
    $envVar = $secretSplit[0]
    $secret = $envVar
    if ($secretSplit.Count -gt 1) {
        $secret = $secretSplit[1]
    }

    $value = $null
    $keyVaultSecret = Get-AzKeyVaultSecret -VaultName $keyVaultCredentials.keyVaultName -Name $secret -ErrorAction SilentlyContinue
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
