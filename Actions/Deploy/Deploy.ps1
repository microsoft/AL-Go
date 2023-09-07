Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Artifacts to deploy", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD",
    [Parameter(HelpMessage = "The settings for all Deployment Environments", Mandatory = $true)]
    [string] $deploymentEnvironmentsJson
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0075' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $deploymentEnvironments = $deploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $deploymentSettings = $deploymentEnvironments."$environmentName"
    $envName = $environmentName.Split(' ')[0]
    $secrets = $env:Secrets | ConvertFrom-Json

    # Check obsolete secrets
    "$($envName)-EnvironmentName","$($envName)_EnvironmentName","EnvironmentName" | ForEach-Object {
        if ($secrets."$_") {
            throw "The secret $_ is obsolete and should be replaced by using the EnvironmentName property in the DeployTo$envName setting in .github/AL-Go-Settings.json instead"
        }
    }
    if ($secrets.Projects) {
        throw "The secret Projects is obsolete and should be replaced by using the Projects property in the DeployTo$envName setting in .github/AL-Go-Settings.json instead"
    }

    $authContext = $null
    foreach($secretName in "$($envName)-AuthContext","$($envName)_AuthContext","AuthContext") {
        if ($secrets."$secretName") {
            $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$secretName"))
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

    $artifacts = $artifacts.Replace('/',([System.IO.Path]::DirectorySeparatorChar)).Replace('\',([System.IO.Path]::DirectorySeparatorChar))

    $apps = @()
    $artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"
    $artifactsFolderCreated = $false
    if ($artifacts -eq ".artifacts") {
        $artifacts = $artifactsFolder
    }

    $searchArtifacts = $false
    if ($artifacts -like "$($ENV:GITHUB_WORKSPACE)*") {
        if (Test-Path $artifacts -PathType Container) {
            $deploymentSettings.Projects.Split(',') | ForEach-Object {
                $project = $_.Replace('\','_').Replace('/','_')
                $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
                Write-Host "project '$project'"
                $apps += @((Get-ChildItem -Path $artifacts -Filter "$project-$refname-Apps-*.*.*.*") | ForEach-Object { $_.FullName })
                if (!($apps)) {
                    throw "There is no artifacts present in $artifacts matching $project-$refname-Apps-<version>."
                }
                $apps += @((Get-ChildItem -Path $artifacts -Filter "$project-$refname-Dependencies-*.*.*.*") | ForEach-Object { $_.FullName })
            }
        }
        elseif (Test-Path $artifacts) {
            $apps = $artifacts
        }
        else {
            throw "Artifact $artifacts was not found. Make sure that the artifact files exist and files are not corrupted."
        }
    }
    elseif ($artifacts -eq "current" -or $artifacts -eq "prerelease" -or $artifacts -eq "draft") {
        # latest released version
        $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        if ($releases) {
            if ($artifacts -eq "current") {
                $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
            }
            elseif ($artifacts -eq "prerelease") {
                $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
            }
            elseif ($artifacts -eq "draft") {
                $release = $releases | Select-Object -First 1
            }
            if (!($release)) {
                throw "Unable to locate $artifacts release"
            }
            New-Item $artifactsFolder -ItemType Directory | Out-Null
            $artifactsFolderCreated = $true
            DownloadRelease -token $token -projects $deploymentSettings.Projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Apps"
            DownloadRelease -token $token -projects $deploymentSettings.Projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Dependencies"
            $apps = @((Get-ChildItem -Path $artifactsFolder) | ForEach-Object { $_.FullName })
            if (!$apps) {
                throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
            }
        }
        else {
            if ($artifacts -eq "current") {
                Write-Host "::Warning::Current release was specified, but no releases were found. Searching for latest build artifacts instead."
                $artifacts = "latest"
                $searchArtifacts = $true
            }
            else {
                throw "Artifact $artifacts was not found on any release."
            }
        }
    }
    else {
        $searchArtifacts = $true
    }

    if ($searchArtifacts) {
        New-Item $artifactsFolder -ItemType Directory | Out-Null
        $allArtifacts = @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Apps" -projects $deploymentSettings.Projects -Version $artifacts -branch "main")
        $allArtifacts += @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Dependencies" -projects $deploymentSettings.Projects -Version $artifacts -branch "main")
        if ($allArtifacts) {
            $allArtifacts | ForEach-Object {
                $appFile = DownloadArtifact -token $token -artifact $_ -path $artifactsFolder
                if (!(Test-Path $appFile)) {
                    throw "Unable to download artifact $($_.name)"
                }
                $apps += @($appFile)
            }
        }
        else {
            throw "Could not find any Apps artifacts for projects $($deploymentSettings.Projects), version $artifacts"
        }
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

        Write-Host "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$($deploymentSettings.EnvironmentName)/deployment/url"
        $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$($deploymentSettings.EnvironmentName)/deployment/url"
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
            if ($sandboxEnvironment -and !($bcAuthContext.ClientSecret)) {
                # Sandbox and not S2S -> use dev endpoint (Publish-BcContainerApp)
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
                Publish-BcContainerApp @parameters -useDevEndpoint -checkAlreadyInstalled -excludeRuntimePackages
            }
            elseif (!$sandboxEnvironment -and $type -eq 'CD' -and !($deploymentSettings.ContinuousDeployment)) {
                # Continuous deployment is undefined in settings - we will not deploy to production environments
                Write-Host "::Warning::Ignoring environment $($deploymentSettings.EnvironmentName), which is a production environment"
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

    if ($artifactsFolderCreated) {
        Remove-Item $artifactsFolder -Recurse -Force
    }

    TrackTrace -telemetryScope $telemetryScope

}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
