Param(
    [string] $actor,
    [string] $token,
    [string] $environmentName,
    [string] $artifactsUrl,
    [boolean] $appSourceApp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper

    if ($artifactsUrl -like "$($ENV:GITHUB_WORKSPACE)*") {
        $apps = (Get-ChildItem $artifactsUrl -filter '*.app' -Recurse).FullName
    }
    elseif ($artifactsUrl -eq "current" -or $artifactsUrl -eq "prerelease" -or $artifactsUrl -eq "draft") {
        # latest released version
        $releases = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
        if ($artifactsUrl -eq "current") {
            $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
        }
        elseif ($artifactsUrl -eq "prerelease") {
            $release = $releases | Where-Object { -not ($_.draft) } | Select-Object -First 1
        }
        elseif ($artifactsUrl -eq "draft") {
            $release = $releases | Select-Object -First 1
        }
        if (!($release)) {
            OutputError -message "Unable to locate $artifactsUrl release"
            exit
        }
        $apps = DownloadRelease -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $release
        if (!($apps)) {
            OutputError -message "Unable to download $artifactsUrl release"
            exit
        }
    }
    else {
        if ($artifactsUrl -like "https://*") {
            $artifact = GetArtifact -token $token -artifactsUrl $artifactsUrl
        }
        else {
            $artifacts = GetArtifacts -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
            if ($artifactsUrl -eq "latest") {
                $artifact = $artifacts | Select-Object -First 1
            }
            else {
                $artifact = $artifacts | Where-Object { $_.name -like "*-Apps-$artifactsUrl" }
            }
        }
        if (!($artifact)) {
            OutputError -message "Unable to locate artifact"
            exit
        }
        $apps = DownloadArtifact -token $token -artifact $artifact
        if (!($apps)) {
            OutputError -message "Unable to download artifact"
            exit
        }
    }

    Set-Location $ENV:GITHUB_WORKSPACE
    if (-not ($ENV:AUTHCONTEXT)) {
        OutputError -message "You need to create an environment secret called AUTHCONTEXT containing authentication information for the environment"
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
    try {
        if ($appSourceApp) {
            Publish-BcContainerApp -bcAuthContext $bcAuthContext -environment $envName -appFile $apps -useDevEndpoint
        }
        else {
            Publish-PerTenantExtensionApps -bcAuthContext $bcAuthContext -environment $envName -appFiles $apps
        }
    }
    catch {
        OutputError -message "Error deploying to $environmentName. Error was $($_.Exception.Message)"
        exit 1
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
