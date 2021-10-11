Param(
    [string] $actor,
    [string] $token,
    [string] $projects = "*",
    [string] $environmentName,
    [string] $artifacts,
    [ValidateSet('CD','Publish')]
    [string] $type
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper

    if ($projects -eq '') { $projects = "*" }

    $apps = @()
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE "artifacts"

    if ($artifacts -like "$($baseFolder)*") {
        $apps
        if (Test-Path $artifacts -PathType Container) {
            $apps = @((Get-ChildItem -Path $artifacts -Filter "*-Apps-*") | ForEach-Object { $_.FullName })
            if (!($apps)) {
                OutputError -message "No artifacts present in $artifacts"
                exit
            }
        }
        elseif (Test-Path $artifacts) {
            $apps = $artifacts
        }
        else {
            OutputError -message "Unable to use artifact $artifacts"
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
            OutputError -message "Unable to locate $artifacts release"
            exit
        }
        New-Item $baseFolder -ItemType Directory | Out-Null
        DownloadRelease -token $token -projects $projects -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release -path $baseFolder
        $apps = @((Get-ChildItem -Path $baseFolder) | ForEach-Object { $_.FullName })
        if (!$apps) {
            OutputError -message "Unable to download $artifacts release"
            exit
        }
    }
    else {
        New-Item $baseFolder -ItemType Directory | Out-Null
        $allArtifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        $artifactsVersion = $artifacts
        if ($artifacts -eq "latest") {
            $artifact = $allArtifacts | Where-Object { $_.name -like "*-Apps-*" } | Select-Object -First 1
            $artifactsVersion = $artifact.name.SubString($artifact.name.IndexOf('-Apps-')+6)
        }
        $projects.Split(',') | ForEach-Object {
            $project = $_
            $allArtifacts | Where-Object { $_.name -like "$project-Apps-$artifactsVersion" } | ForEach-Object {
                DownloadArtifact -token $token -artifact $_ -path $baseFolder
            }
        }
        $apps = @((Get-ChildItem -Path $baseFolder) | ForEach-Object { $_.FullName })
        if (!($apps)) {
            OutputError -message "Unable to download artifact $project-Apps-$artifacts"
            exit
        }
    }

    Set-Location $baseFolder
    if (-not ($ENV:AUTHCONTEXT)) {
        OutputError -message "You need to create an environment secret called AUTHCONTEXT containing authentication information for the environment $environmentName"
        exit 1
    }

    try {
        $authContextParams = $ENV:AUTHCONTEXT | ConvertFrom-Json | ConvertTo-HashTable
        $bcAuthContext = New-BcAuthContext @authContextParams
    } catch {
        OutputError -message "Error trying to authenticate. Error was $($_.exception.message)"
        exit 1
    }

    $envName = $environmentName.Split(' ')[0]
    $environment = Get-BcEnvironments -bcAuthContext $bcAuthContext | Where-Object { $_.Name -eq $envName }
    if (-not ($environment)) {
        OutputError -message "Environment with name $envName does not exist in the current authorization context."
        exit 1
    }

    $apps | ForEach-Object {
        try {
            if ($environment.type -eq "Sandbox") {
                Write-Host "Publishing apps using development endpoint"
                Publish-BcContainerApp -bcAuthContext $bcAuthContext -environment $envName -appFile $_ -useDevEndpoint
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
            OutputError -message "Error deploying to $environmentName. Error was $($_.Exception.Message)"
            exit 1
        }
    }
}
catch {
    OutputError -message $_.Exception.Message
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
