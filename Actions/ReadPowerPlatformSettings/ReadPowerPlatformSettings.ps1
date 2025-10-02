param(
    [Parameter(Mandatory = $true)]
    [string] $environmentName
)
$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

$envName = $environmentName.Split(' ')[0]

$settings = $env:Settings | ConvertFrom-Json

# Default deployment settings
$deploymentSettings = @{
    "EnvironmentType" = "SaaS"
    "EnvironmentName" = $envName
    "Projects" = @('*')
    "DependencyInstallMode" = "install"  # ignore, install, upgrade or forceUpgrade
    "SyncMode" = $null
    "Scope" = $null
    "buildMode" = $null
    "continuousDeployment" = $null
    "companyId" = ''
    "ppEnvironmentUrl" = ''
    "includeTestAppsInSandboxEnvironment" = $false
    "excludeAppIds" = @()
}

# If there is a deployTo<environamentName> settings, overwrite the default settings
$settingsName = "deployTo$($envName)"
if($settings.PSObject.Properties.Name -contains $settingsName) {
    Write-Host "Using custom settings for environment $environmentName"

    $customDeploymentSettings = $settings."$settingsName"
    foreach ($key in $customDeploymentSettings.PSObject.Properties.Name) {
        $deploymentSettings.$key = $customDeploymentSettings.$key
    }
}

foreach($property in 'ppEnvironmentUrl','companyId','environmentName') {
    if ($deploymentSettings.Keys -contains $property) {
        Write-Host "Setting $property"
        Add-Content -Encoding utf8 -Path $env:GITHUB_OUTPUT -Value "$property=$($deploymentSettings."$property")"
    }
    else {
        throw "DeployTo$envName setting must contain '$property' property" # Defensive check
    }
}

# Make sure required settings are not empty
foreach($property in 'ppEnvironmentUrl','companyId','environmentName') {
    if ([string]::IsNullOrWhiteSpace($deploymentSettings."$property")) {
        throw "DeployTo$envName setting must contain '$property' property"
    }
}

$secrets = $env:Secrets | ConvertFrom-Json

# Read the authentication context from secrets
$authContext = $null
foreach($secretName in "$($envName)-AuthContext","$($envName)_AuthContext","AuthContext") {
    if ($secrets.PSObject.Properties.Name -contains "$secretName") {
        Write-Host "Setting authentication context from secret $secretName"
        $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName")) | ConvertFrom-Json
        'ppTenantId','ppApplicationId','ppClientSecret','ppUserName','ppPassword' | ForEach-Object {
            if ($authContext.PSObject.Properties.Name -eq $_) {
                Write-Host "Setting $_"
                Add-Content -Encoding utf8 -Path $env:GITHUB_OUTPUT -Value "$_=$($authContext."$_")"
                Set-Variable -Name $_ -Value $authContext."$_"
            }
            else {
                Add-Content -Encoding utf8 -Path $env:GITHUB_OUTPUT -Value "$_="
                Set-Variable -Name $_ -Value ""
            }
        }

        if ($ppApplicationId -and $ppClientSecret -and $ppTenantId) {
            Write-Host "Authenticating with application ID and client secret"
        }
        elseif ($ppUserName -and $ppPassword) {
            Write-Host "Authenticating with user name"
        }
        else {
            throw "Secret $secretName must contain either 'ppUserName' and 'ppPassword' properties or 'ppApplicationId', 'ppClientSecret' and 'ppTenantId' properties"
        }
        break
    }
}

# Verify the authentication context has been set
if ($null -eq $authContext) {
    throw "Unable to find authentication context for GitHub environment $envName in secrets"
}
