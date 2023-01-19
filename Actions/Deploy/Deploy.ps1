Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Projects to deploy", Mandatory = $false)]
    [string] $projects = '',
    [Parameter(HelpMessage = "Name of environment to deploy to", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Artifacts to deploy", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

if ($projects -eq '') {
    Write-Host "No projects to deploy"
}
else {

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0075' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $EnvironmentName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($environmentName))

    $artifacts = $artifacts.Replace('/',([System.IO.Path]::DirectorySeparatorChar)).Replace('\',([System.IO.Path]::DirectorySeparatorChar))

    $apps = @()
    $artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE ".artifacts"
    $artifactsFolderCreated = $false
    if ($artifacts -eq ".artifacts") {
        $artifacts = $artifactsFolder
    }

    if ($artifacts -like "$($ENV:GITHUB_WORKSPACE)*") {
        if (Test-Path $artifacts -PathType Container) {
            $projects.Split(',') | ForEach-Object {
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
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Apps"
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $artifactsFolder -mask "Dependencies"
        $apps = @((Get-ChildItem -Path $artifactsFolder) | ForEach-Object { $_.FullName })
        if (!$apps) {
            throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
        }
    }
    else {
        New-Item $artifactsFolder -ItemType Directory | Out-Null
        $baseFolderCreated = $true
        $allArtifacts = @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Apps" -projects $projects -Version $artifacts -branch "main")
        $allArtifacts += @(GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Dependencies" -projects $projects -Version $artifacts -branch "main")
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
            throw "Could not find any Apps artifacts for projects $projects, version $artifacts"
        }
    }

    Write-Host "Apps to deploy"
    $apps | Out-Host

    Set-Location $ENV:GITHUB_WORKSPACE
    if (-not ($ENV:AuthContext)) {
        throw "An environment secret for environment($environmentName) called AUTHCONTEXT containing authentication information for the environment was not found.You must create an environment secret."
    }
    $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ENV:AuthContext))

    try {
        $authContextParams = $authContext | ConvertFrom-Json | ConvertTo-HashTable
        $bcAuthContext = New-BcAuthContext @authContextParams
    } catch {
        throw "Authentication failed. $([environment]::Newline) $($_.exception.message)"
    }

    $envName = $environmentName.Split(' ')[0]
    Write-Host "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$envName/deployment/url"
    $response = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$($bcContainerHelperConfig.baseUrl.TrimEnd('/'))/$($bcAuthContext.tenantId)/$envName/deployment/url"
    if ($response.Status -eq "DoesNotExist") {
        OutputError -message "Environment with name $envName does not exist in the current authorization context."
        exit
    }
    if ($response.Status -ne "Ready") {
        OutputError -message "Environment with name $envName is not ready (Status is $($response.Status))."
        exit
    }

    try {
        if ($response.environmentType -eq 1) {
            if ($bcAuthContext.ClientSecret) {
                Write-Host "Using S2S, publishing apps using automation API"
                Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $apps
            }
            else {
                Write-Host "Publishing apps using development endpoint"
                Publish-BcContainerApp -bcAuthContext $bcAuthContext -environment $envName -appFile $apps -useDevEndpoint -checkAlreadyInstalled
            }
        }
        else {
            if ($type -eq 'CD') {
                Write-Host "Ignoring environment $environmentName, which is a production environment"
            }
            else {
                # Check for AppSource App - cannot be deployed
                Write-Host "Publishing apps using automation API"
                Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $apps
            }
        }
    }
    catch {
        OutputError -message "Deploying to $environmentName failed.$([environment]::Newline) $($_.Exception.Message)"
        exit
    }

    if ($artifactsFolderCreated) {
        Remove-Item $artifactsFolder -Recurse -Force
    }

    TrackTrace -telemetryScope $telemetryScope

}
catch {
    OutputError -message "Deploy action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
}
