Param(
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Path to the downloaded artifacts to deploy", Mandatory = $true)]
    [string] $artifactsFolder,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "The settings for all Deployment Environments", Mandatory = $true)]
    [string] $deploymentEnvironmentsJson
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$deploymentEnvironments = $deploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
$deploymentSettings = $deploymentEnvironments."$environmentName"
$buildMode = $deploymentSettings.buildMode
if ($null -eq $buildMode -or $buildMode -eq 'default') {
    $buildMode = ''
}
$envName = $environmentName.Split(' ')[0]
$secrets = $env:Secrets | ConvertFrom-Json
$settings = $env:Settings | ConvertFrom-Json

$authContext = $null
foreach($secretName in "$($envName)-AuthContext","$($envName)_AuthContext","AuthContext") {
    if ($secrets."$secretName") {
        $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName"))
        break
    }
}
if (-not $authContext) {
    # No AuthContext secret provided, if deviceCode is present, use it - else give an error
    if ($env:deviceCode) {
        $authContext = "{""deviceCode"":""$($env:deviceCode)""}"
    }
    else {
        throw "No Authentication Context found for environment ($environmentName). You must create an environment secret called AUTHCONTEXT or a repository secret called $($envName)_AUTHCONTEXT."
    }
}

$apps = @()
$artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
if (Test-Path $artifactsFolder -PathType Container) {
    $deploymentSettings.Projects.Split(',') | ForEach-Object {
        $project = $_.Replace('\','_').Replace('/','_')
        $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
        Write-Host "project '$project'"
        $projectApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildMode)Apps-*.*.*.*") | ForEach-Object { $_.FullName })
        if (!($projectApps)) {
            if ($project -ne '*') {
                throw "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildMode)Apps-<version>."
            }
        }
        else {
            $apps += $projectApps
        }
    }
}
else {
    throw "Artifact $artifactsFolder was not found. Make sure that the artifact files exist and files are not corrupted."
}

Write-Host "Apps to deploy"
$apps | Out-Host

Set-Location $ENV:GITHUB_WORKSPACE

$customScript = Join-Path $ENV:GITHUB_WORKSPACE ".github/DeployTo$($deploymentSettings.EnvironmentType).ps1"
if (Test-Path $customScript) {
    Write-Host "Executing custom deployment script $customScript"
    $parameters = @{
        "type" = $type
        "AuthContext" = $authContext
        "Apps" = $apps
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
            if ($settings.Type -eq 'AppSource App' -or ($sandboxEnvironment -and !($bcAuthContext.ClientSecret -or $bcAuthContext.ClientAssertion))) {
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
        elseif ($scope -eq 'Dev') {
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
            Write-Host "Publishing apps using automation API"
            Publish-PerTenantExtensionApps @parameters
        }
    }
    catch {
        OutputError -message "Deploying to $environmentName failed.$([environment]::Newline) $($_.Exception.Message)"
        exit
    }
}
