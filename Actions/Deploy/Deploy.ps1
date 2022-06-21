Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Projects to deploy (default is all)", Mandatory = $false)]
    [string] $projects = "*",
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

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0075' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $EnvironmentName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($environmentName))

    if ($projects -eq '') { $projects = "*" }

    $apps = @()
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE "artifacts"

    if ($artifacts -like "$($baseFolder)*") {
        $apps
        if (Test-Path $artifacts -PathType Container) {
            $apps = @((Get-ChildItem -Path $artifacts -Filter "*-Apps-*") | ForEach-Object { $_.FullName })
            if (!($apps)) {
                throw "There is no artifacts present in $artifacts."
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
        New-Item $baseFolder -ItemType Directory | Out-Null
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $baseFolder
        $apps = @((Get-ChildItem -Path $baseFolder) | ForEach-Object { $_.FullName })
        if (!$apps) {
            throw "Artifact $artifacts was not found on any release. Make sure that the artifact files exist and files are not corrupted."
        }
    }
    else {
        New-Item $baseFolder -ItemType Directory | Out-Null
        $allArtifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask "Apps" -projects $projects -Version $artifacts -branch "main"
        if ($allArtifacts) {
            $allArtifacts | ForEach-Object {
                $appFile = DownloadArtifact -token $token -artifact $_ -path $baseFolder
                if (!(Test-Path $appFile)) {
                    throw "Unable to download artifact $($_.name)"
                }
            }
        }
        else {
            throw "Could not find any Apps artifacts for projects $projects, version $artifacts"
        }
    }

    Set-Location $baseFolder
    if (-not ($ENV:AUTHCONTEXT)) {
        throw "An environment secret for environment($environmentName) called AUTHCONTEXT containing authentication information for the environment was not found.You must create an environment secret."
    }
    $authContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ENV:AUTHCONTEXT))

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

    $apps | ForEach-Object {
        try {
            if ($response.environmentType -eq 1) {
                if ($bcAuthContext.ClientSecret) {
                    Write-Host "Using S2S, publishing apps using automation API"
                    Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $_
                }
                else {
                    Write-Host "Publishing apps using development endpoint"
                    Publish-BcContainerApp -bcAuthContext $bcAuthContext -environment $envName -appFile $_ -useDevEndpoint
                }
            }
            else {
                if ($type -eq 'CD') {
                    Write-Host "Ignoring environment $environmentName, which is a production environment"
                }
                else {

                    # Check for AppSource App - cannot be deployed

                    Write-Host "Publishing apps using automation API"
                    Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $_
                }
            }
        }
        catch {
            OutputError -message "Deploying to $environmentName failed.$([environment]::Newline) $($_.Exception.Message)"
            exit
        }
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
