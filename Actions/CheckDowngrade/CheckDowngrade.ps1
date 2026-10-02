<#
.SYNOPSIS
    Fails the deployment if an app in the build artifact has a lower version than the version installed in the target Business Central environment.
.DESCRIPTION
    Without this check, deploying an app whose app.json version is lower than the installed version completes successfully (green checkmark).
    The check runs only when failOnAppVersionDowngrade is enabled globally or in DeployTo<environmentName>.
    The check is skipped for environments deployed using a custom .github/DeployTo<EnvironmentType>.ps1 script.
#>
Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Name of environment to validate", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Path to the downloaded artifacts to validate", Mandatory = $true)]
    [string] $artifactsFolder,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "The settings for all Deployment Environments", Mandatory = $true)]
    [string] $deploymentEnvironmentsJson,
    [Parameter(HelpMessage = "Artifacts version. Used to check if this is a deployment from a PR", Mandatory = $false)]
    [string] $artifactsVersion = '',
    [Parameter(HelpMessage = "Fail when an artifact app version is lower than the installed version", Mandatory = $false)]
    [bool] $failOnAppVersionDowngrade = $false
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\Deploy\Deploy.psm1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

if (-not $failOnAppVersionDowngrade) {
    Write-Host "Downgrade check is disabled."
    return
}

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
$deploymentSettings = GetDeploymentSettings -deploymentEnvironmentsJson $deploymentEnvironmentsJson -environmentName $environmentName -settings $settings

# Mirror Deploy.ps1: environments handled by a custom DeployTo<EnvironmentType>.ps1 script are not deployed through the built-in SaaS path
$githubFolder = Join-Path $ENV:GITHUB_WORKSPACE '.github'
if (Test-Path -Path $githubFolder -PathType Container) {
    $customScript = Get-ChildItem -Path $githubFolder | Where-Object { $_.Name -eq "DeployTo$($deploymentSettings.EnvironmentType).ps1" }
    if ($customScript) {
        OutputNotice -message "Downgrade check skipped for environment '$environmentName' because it is deployed using the custom deployment script $($customScript.Name)."
        return
    }
}

DownloadAndImportBcContainerHelper

$envName = $environmentName.Split(' ')[0]
$secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable -recurse
$authContext = $null
foreach ($secretName in "$($envName)-AuthContext", "$($envName)_AuthContext", "AuthContext") {
    if ($secrets.ContainsKey($secretName) -and $secrets."$secretName") {
        $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName"))
        Write-Host "::add-mask::$authContext"
        break
    }
}
if (-not $authContext) {
     if ($env:deviceCode) {
         $authContext = "{""deviceCode"":""$($env:deviceCode)""}"
     }
     # Mirror Deploy.ps1: CD silently skips environments without AuthContext unless continuousDeployment is set
     elseif ($type -eq 'CD' -and -not ($deploymentSettings.ContainsKey('continuousDeployment') -and $deploymentSettings.continuousDeployment)) {
         OutputNotice -message "Downgrade check skipped for environment '$environmentName' because no Authentication Context was found."
         return
     }
     else {
         throw "No Authentication Context found for environment ($environmentName)."
     }
 }

$authContextParams = $authContext | ConvertFrom-Json | ConvertTo-HashTable -recurse
$bcAuthContext = New-BcAuthContext @authContextParams
if ($null -eq $bcAuthContext) {
    throw "Authentication failed for environment '$environmentName'."
}

# Validate the apps that the Deploy action will deploy (including test apps when includeTestAppsInSandboxEnvironment is enabled)
$appsToDeploy, $null = GetAppsAndDependenciesFromArtifacts -token $token -artifactsFolder $artifactsFolder -deploymentSettings $deploymentSettings -artifactsVersion $artifactsVersion
$appsToDeploy = @($appsToDeploy | Where-Object { $_ })

if (-not $appsToDeploy) {
    Write-Host "No apps to deploy found for downgrade validation in '$artifactsFolder'."
    return
}

$installedApps = Get-BcInstalledExtensions -bcAuthContext $bcAuthContext -environment $deploymentSettings.EnvironmentName |
    Where-Object { $_.isInstalled }

$violations = @()
foreach ($appFile in $appsToDeploy) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile
    $installedApp = $installedApps | Where-Object { $_.id -eq $appJson.id }
    if (-not $installedApp) {
        continue
    }

    $artifactVersion = [version]::new($appJson.version)
    $installedVersion = [version]::new($installedApp.versionMajor, $installedApp.versionMinor, $installedApp.versionBuild, $installedApp.versionRevision)

    if ($artifactVersion -lt $installedVersion) {
        $violations += "App '$($appJson.name)' is already installed in version $installedVersion, which is higher than artifact version $artifactVersion."
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object {
        Write-Host "::Error::$_"
    }
    throw "Downgrade check failed: one or more apps in the artifact are lower than installed versions in '$environmentName'."
}

Write-Host "Downgrade check passed for environment '$environmentName'."
