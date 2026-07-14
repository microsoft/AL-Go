Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Path to the downloaded artifacts to deploy", Mandatory = $true)]
    [string] $artifactsFolder,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "The settings for all Deployment Environments", Mandatory = $true)]
    [string] $deploymentEnvironmentsJson,
    [Parameter(HelpMessage = "Artifacts version. Used to check if this is a deployment from a PR", Mandatory = $false)]
    [string] $artifactsVersion = ''
)

Import-Module (Join-Path -Path $PSScriptRoot "Deploy.psm1")
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$deploymentEnvironments = $deploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
$deploymentSettings = $deploymentEnvironments."$environmentName"

$envName = $environmentName.Split(' ')[0]
$secrets = $env:Secrets | ConvertFrom-Json
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse

# Check DeployTo<environmentName> setting (it could have been added in the environment-specific settings)
$settingsName = "DeployTo$envName"
if ($settings.ContainsKey($settingsName)) {
    # If a DeployTo<environmentName> setting exists - use values from this (over the defaults)
    Write-Host "Setting $settingsName"
    $deployTo = $settings."$settingsName"
    $keys = @($deployTo.Keys)
    foreach($key in $keys) {
        if ($deploymentSettings.ContainsKey($key)) {
            if ($null -ne $deploymentSettings."$key" -and $null -ne $deployTo."$key" -and $deploymentSettings."$key".GetType().Name -ne $deployTo."$key".GetType().Name) {
                if ($key -eq "runs-on" -and $deployTo."$key" -is [Object[]]) {
                    # Support setting runs-on as an array in settings to not break old settings
                    # See https://github.com/microsoft/AL-Go/issues/1182
                    $deployTo."$key" = $deployTo."$key" -join ','
                }
                else {
                    Write-Host "::WARNING::The property $key in $settingsName is expected to be of type $($deploymentSettings."$key".GetType().Name)"
                }
            }
            Write-Host "Property $key = $($deployTo."$key")"
            $deploymentSettings."$key" = $deployTo."$key"
        }
        else {
            $deploymentSettings += @{
                "$key" = $deployTo."$key"
            }
        }
    }
}

$authContext = $null
foreach($secretName in "$($envName)-AuthContext","$($envName)_AuthContext","AuthContext") {
    if ($secrets."$secretName") {
        $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName"))
        break
    }
}
if (-not $authContext) {
    $msg = "No Authentication Context found for environment ($environmentName). You must create an environment secret called AUTHCONTEXT or a repository secret called $($envName)_AUTHCONTEXT in order to deploy to this environment."
    # No AuthContext secret provided, if deviceCode is present, use it - else give an error
    if ($env:deviceCode) {
        $authContext = "{""deviceCode"":""$($env:deviceCode)""}"
    }
    elseif ($type -eq 'CD' -and (-not $deploymentSettings.continuousDeployment)) {
        # Continuous Deployment is undefined in settings - we will not ignore the environment if no AuthContext is provided
        OutputNotice -message $msg
        exit
    }
    else {
        throw $msg
    }
}

$apps = @()
$dependencies = @()
$apps, $dependencies = GetAppsAndDependenciesFromArtifacts -token $token -artifactsFolder $artifactsFolder -deploymentSettings $deploymentSettings -artifactsVersion $artifactsVersion

# Calculate unknown dependencies for all apps and known dependencies
$unknownDependencies = @()
Sort-AppFilesByDependencies -appFiles @($apps + $dependencies) -unknownDependencies ([ref]$unknownDependencies) -WarningAction SilentlyContinue | Out-Null

Write-Host "Apps to deploy"
$apps | ForEach-Object {
    Write-Host "- $([System.IO.Path]::GetFileName($_))"
}

if ($deploymentSettings.DependencyInstallMode -ne "ignore") {
    Write-Host "Dependencies to $($deploymentSettings.DependencyInstallMode)"
    if ($dependencies) {
        $dependencies | ForEach-Object {
            Write-Host "- $([System.IO.Path]::GetFileName($_))"
        }
    }
    else {
        Write-Host "- None"
    }
}

Set-Location $ENV:GITHUB_WORKSPACE

# Use Get-ChildItem to support Linux (case sensitive filenames) as well as Windows
$customScript = Get-ChildItem -Path (Join-Path $ENV:GITHUB_WORKSPACE '.github') | Where-Object { $_.Name -eq "DeployTo$($deploymentSettings.EnvironmentType).ps1" } | ForEach-Object { $_.FullName }
if ($customScript) {
    Write-Host "Executing custom deployment script $customScript"
    $parameters = @{
        "type" = $type
        "AuthContext" = $authContext
        "Apps" = $apps
        "Dependencies" = $dependencies
    } + $deploymentSettings
    . $customScript -parameters $parameters
}
else {
    try {
        $authContextParams = $authContext | ConvertFrom-Json | ConvertTo-HashTable
        $bcAuthContext = New-BcAuthContext @authContextParams
        if ($null -eq $bcAuthContext) {
            throw "Authentication failed"
        }
    } catch {
        throw "Authentication failed. $([environment]::Newline) $($_.exception.message)"
    }

    $environmentUrl = "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$($deploymentSettings.EnvironmentName)"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "environmentUrl=$environmentUrl"
    Write-Host "EnvironmentUrl: $environmentUrl"
    $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$environmentUrl/deployment/url"
    if ($response.Status -eq "DoesNotExist") {
        OutputError -message "Environment with name $($deploymentSettings.EnvironmentName) does not exist in the current authorization context."
        exit
    }
    if ($response.Status -ne "Ready") {
        OutputError -message "Environment with name $($deploymentSettings.EnvironmentName) is not ready (Status is $($response.Status))."
        exit
    }

    try {
        $sandboxEnvironment = ($response.environmentType -eq 1)
        $scope = $deploymentSettings.Scope
        if ($null -eq $scope) {
            if ($settings.type -eq 'AppSource App' -or ($sandboxEnvironment -and !($bcAuthContext.ClientSecret -or $bcAuthContext.ClientAssertion))) {
                # Sandbox and not S2S -> use dev endpoint (Publish-BcContainerApp)
                $scope = 'Dev'
            }
            else {
                $scope = 'PTE'
            }
        }
        elseif (@('Dev','PTE') -notcontains $scope) {
            throw "Invalid Scope $($scope). Valid values are Dev and PTE."
        }
        if (!$sandboxEnvironment -and $type -eq 'CD' -and !($deploymentSettings.continuousDeployment)) {
            # Continuous deployment is undefined in settings - we will not deploy to production environments
            Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment"
        }
        elseif (!$sandboxEnvironment -and $deploymentSettings.includeTestAppsInSandboxEnvironment) {
            Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment, as test apps can only be deployed to sandbox environments"
        }
        elseif (!$sandboxEnvironment -and $artifactsVersion -like "PR_*") {
            Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment, as deploying from a PR is only supported in sandbox environments"
        }
        else {
            if ($dependencies) {
                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $deploymentSettings.EnvironmentName -Apps $dependencies -installMode $deploymentSettings.DependencyInstallMode
            }
            if ($unknownDependencies) {
                InstallUnknownDependencies -bcAuthContext $bcAuthContext -environment $deploymentSettings.EnvironmentName -Apps $unknownDependencies -installMode $deploymentSettings.DependencyInstallMode
            }
            if ($scope -eq 'Dev') {
                if (!$sandboxEnvironment) {
                    throw "Scope Dev is only valid for sandbox environments"
                }
                $parameters = @{
                    "bcAuthContext" = $bcAuthContext
                    "environment" = $deploymentSettings.EnvironmentName
                    "appFile" = $apps
                }
                if ($deploymentSettings.SyncMode) {
                    if (@('Add','ForceSync', 'Clean', 'Development') -notcontains $deploymentSettings.SyncMode) {
                        throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the development endpoint. Valid values are Add, ForceSync, Development and Clean."
                    }
                    Write-Host "Using $($deploymentSettings.SyncMode)"
                    $parameters += @{ "SyncMode" = $deploymentSettings.SyncMode }
                }
                Write-Host "Publishing apps using development endpoint"
                Publish-BcContainerApp @parameters -useDevEndpoint -checkAlreadyInstalled -excludeRuntimePackages -replacePackageId
            }
            else {
                # Use automation API for production environments (Publish-PerTenantExtensionApps)
                $parameters = @{
                    "bcAuthContext" = $bcAuthContext
                    "environment" = $deploymentSettings.EnvironmentName
                    "appFiles" = $apps
                }
                if ($deploymentSettings.SyncMode) {
                    if (@('Add','ForceSync') -notcontains $deploymentSettings.SyncMode) {
                        throw "Invalid SyncMode $($deploymentSettings.SyncMode) when deploying using the automation API. Valid values are Add and ForceSync."
                    }
                    Write-Host "Using $($deploymentSettings.SyncMode)"
                    $syncMode = $deploymentSettings.SyncMode
                    if ($syncMode -eq 'ForceSync') { $syncMode = 'Force' }
                    $parameters += @{ "SchemaSyncMode" = $syncMode }
                }

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $deploymentSettings.EnvironmentName -appFiles $apps

                Write-Host "Publishing apps using automation API"
                Publish-PerTenantExtensionApps @parameters
            }
        }
    }
    catch {
        OutputError -message "Deploying to $environmentName failed.$([environment]::Newline) $($_.Exception.Message)"
        exit
    }
}
