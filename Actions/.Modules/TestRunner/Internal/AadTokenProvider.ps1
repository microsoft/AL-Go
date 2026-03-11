# Example test script for using Cloud Migration APIs E2E
# API documentation is here: https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/administration/cloudmigrationapi/cloud-migration-api-overview?branch=cloud-migration-api
# Run the "Install-Module -Name MSAL.PS" command on the first run, unless you have installed MSAL.PS. This function is used to obtain the token

# Specify the name of the module you want to check/install
$moduleName = "MSAL.PS"

# Check if the module is already installed
if (-not (Get-Module -Name $moduleName -ListAvailable)) {
    # Module is not installed, so install it
    Write-Host "Installing $moduleName..."
    Install-Module -Name $moduleName -Force -Scope AllUsers # Use -Scope CurrentUser or -Scope AllUsers as needed
}

Import-Module $moduleName

class AadTokenProvider
{
    [string] $AADTenantID
    [string] $ClientId
    [string] $RedirectUri
    [string] $CurrentToken
    [DateTimeOffset] $TokenExpirationTime
    [Array] $BcScopes
    [string] $AuthorityUri

    AadTokenProvider([string] $AADTenantID, [string] $ClientId, [string] $RedirectUri)
    {
        $this.Initialize($AADTenantID, $ClientId, $RedirectUri)        
    }

    Initialize([string] $AADTenantID, [string] $ClientId, [string] $RedirectUri)
    {
        $this.AADTenantID = $AADTenantID 
        $this.ClientId = $ClientId
        $this.RedirectUri = $RedirectUri
        $BaseAuthorityUri = "https://login.microsoftonline.com"
        $BcAppIdUri = "https://api.businesscentral.dynamics.com"
        $this.BcScopes = @("$BcAppIdUri/user_impersonation", ("$BcAppIdUri/Financials.ReadWrite.All" ))
        $this.AuthorityUri = "$BaseAuthorityUri/$AADTenantID"
        $this.TokenExpirationTime = (Get-Date)
    }

    [string] GetToken([pscredential] $Credential)
    {   
        
        if($this.TokenExpirationTime)
        {
            if ($this.TokenExpirationTime -gt (Get-Date))
            {
                return $this.CurrentToken
            }
        }

        try
        {
            $AuthenticationResult = Get-MsalToken -ClientId $this.ClientId -RedirectUri $this.RedirectUri -TenantId $this.AADTenantID -Authority $this.AuthorityUri -UserCredential $Credential -Scopes $this.BcScopes
        }
        catch {
           $AuthenticationResult =  Get-MsalToken -ClientId $this.ClientId -RedirectUri $this.RedirectUri -TenantId $this.AADTenantID -Authority $this.AuthorityUri -Prompt SelectAccount -Scopes $this.BcScopes
        }

        $this.CurrentToken =  $AuthenticationResult.AccessToken;
    
        $this.TokenExpirationTime = ($AuthenticationResult.ExpiresOn - (New-TimeSpan -Minutes 3))
        return $AuthenticationResult.AccessToken;
    }
}
