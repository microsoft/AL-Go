$script:gitHubSecrets = $env:Secrets | ConvertFrom-Json
$script:keyvaultConnectionExists = $false
$script:azureRm210 = $false
$script:isKeyvaultSet = $script:gitHubSecrets.PSObject.Properties.Name -eq "AZURE_CREDENTIALS"
$script:escchars = @(' ','!','\"','#','$','%','\u0026','\u0027','(',')','*','+',',','-','.','/','0','1','2','3','4','5','6','7','8','9',':',';','\u003c','=','\u003e','?','@','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z','[','\\',']','^','_',[char]96,'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','{','|','}','~')

function IsKeyVaultSet {
    return $script:isKeyvaultSet
}

function MaskValueInLog {
    Param(
        [string] $key,
        [string] $value
    )

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

    Write-Host "::add-mask::$val2"

    Write-Host "::add-mask::$([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value)))"
}

function GetGithubSecret {
    param (
        [string] $secretName
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
            MaskValueInLog -key $secret -value $value
            Add-Content -Path $env:GITHUB_ENV -Value "$envVar=$value"
            return $value
        }
    }

    return $null
}
	
function Get-KeyVaultCredentials {
    if (-not $script:isKeyvaultSet) {
        throw "AZURE_CREDENTIALS is not set in your repo."
    }   

    try {
        return $script:gitHuBSecrets.AZURE_CREDENTIALS | ConvertFrom-Json
    }
    catch {
        throw "AZURE_CREDENTIALS are wrongly formatted."
    }

    throw "AZURE_CREDENTIALS are missing. In order to use a Keyvault, please add an AZURE_CREDENTIALS secret like explained here: https://docs.microsoft.com/en-us/azure/developer/github/connect-from-azure"
}

function InstallKeyVaultModuleIfNeeded {
    if (-not $script:isKeyvaultSet) {
        return
    }

    $AzKeyVaultModule = Get-InstalledModule -Name 'Az.KeyVault' -erroraction 'silentlycontinue'
    if ($AzKeyVaultModule) {
        Write-Host "Using Az.KeyVault version $($AzKeyVaultModule.Version)"
        Import-Module  'Az.KeyVault' -DisableNameChecking -WarningAction SilentlyContinue
    }
    else {
        $azureRmKeyVaultModule = Get-Module -name 'AzureRm.KeyVault' -ListAvailable | Select-Object -First 1
        if ($azureRmKeyVaultModule) { Write-Host "AzureRm.KeyVault Module is available in version $($azureRmKeyVaultModule.Version)" }
        $azureRmProfileModule = Get-Module -name 'AzureRm.Profile' -ListAvailable | Select-Object -First 1
        if ($azureRmProfileModule) { Write-Host "AzureRm.Profile Module is available in version $($azureRmProfileModule.Version)" }
        if ($azureRmKeyVaultModule -and $azureRmProfileModule -and "$($azureRmKeyVaultModule.Version)" -eq "2.1.0" -and "$($azureRmProfileModule.Version)" -eq "2.1.0") {
            Write-Host "Using AzureRM version 2.1.0"
            $script:azureRm210 = $true
            $azureRmKeyVaultModule | Import-Module -WarningAction SilentlyContinue
            $azureRmProfileModule | Import-Module -WarningAction SilentlyContinue
            Disable-AzureRmDataCollection -WarningAction SilentlyContinue
        }
        else {
            Write-Host "Installing and importing Az.KeyVault." 
            Install-Module 'Az.KeyVault' -Force
            Import-Module  'Az.KeyVault' -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
        }
    }
}

function ConnectAzureKeyVaultIfNeeded {
    param( 
        [string] $subscriptionId,
        [string] $tenantId,
        [string] $clientId ,
        [string] $clientSecret 
    )
    try {
        if ($script:keyvaultConnectionExists) {
            return
        }

        $credential = New-Object PSCredential -argumentList $clientId, (ConvertTo-SecureString $clientSecret -AsPlainText -Force)
        if ($script:azureRm210) {
            Add-AzureRmAccount -ServicePrincipal -Tenant $tenantId -Credential $credential -WarningAction SilentlyContinue | Out-Null
            Set-AzureRmContext -SubscriptionId $subscriptionId -Tenant $tenantId -WarningAction SilentlyContinue | Out-Null
        }
        else {
            Clear-AzContext -Scope Process
            Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
            Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $credential | Out-Null
            Set-AzContext -SubscriptionId $subscriptionId -Tenant $tenantId | Out-Null
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
        [string] $keyVaultName
    )

    if (-not $script:isKeyvaultSet) {
        return $null
    }
        
    if (-not $script:keyvaultConnectionExists) {
            
        InstallKeyVaultModuleIfNeeded
            
        $credentialsJson = Get-KeyVaultCredentials
        ConnectAzureKeyVaultIfNeeded -subscriptionId $credentialsJson.subscriptionId -tenantId $credentialsJson.tenantId -clientId $credentialsJson.clientId -clientSecret $credentialsJson.clientSecret
    }

    $value = ""
    if ($script:azureRm210) {
        $keyVaultSecret = Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $secret -ErrorAction SilentlyContinue
    }
    else {
        $keyVaultSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secret 
    }

    if ($keyVaultSecret) {
        $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(([Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyVaultSecret.SecretValue)))
        MaskValueInLog -key $secret -value $value
        return $value
    }

    return $null
}

function GetSecret {
    param (
        [string] $secret,
        [string] $keyVaultName
    )

    Write-Host "Trying to get the secret($secret) from the github environment."
    $value = GetGithubSecret -secretName $secret
    if ($value) {
        Write-Host "Secret($secret) was retrieved from the github environment."
        return $value
    }

    if ($keyVaultName) {
        Write-Host "Trying to get the secret($secret) from Key Vault ($keyVaultName)."
        $value = GetKeyVaultSecret -secretName $secret -keyVaultName $keyVaultName
        if ($value) {
            Write-Host "Secret($secret) was retrieved from the Key Vault."
            return $value
        }
    }

    Write-Host  "Could not find secret $secret in Github secrets or Azure Key Vault."
    return $null
}
