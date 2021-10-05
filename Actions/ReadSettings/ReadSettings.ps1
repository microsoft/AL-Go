Param(
    [string] $actor,
    [string] $token,
    [string] $release = "N",
    [string] $get = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $settings = ReadSettings -baseFolder $ENV:GITHUB_WORKSPACE -workflowName $env:GITHUB_WORKFLOW
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    if ($getSettings -contains 'appBuild' -or $getSettings -contains 'appRevision') {
        switch ($settings.versioningStrategy -band 15) {
            0 { # Use RUNID
                $settings.appBuild = [Int32]($ENV:GITHUB_RUN_ID)
                $settings.appRevision = 0
            }
            1 { # USE DATETIME
                $settings.appBuild = [Int32]([DateTime]::Now.ToString('yyyyMMdd'))
                $settings.appRevision = [Int32]([DateTime]::Now.ToString('hhmmss'))
            }
            2 { # USE (latest release runnumber).(CI RunNumber) for CI and (latest release runnumber+1).0 for Release
                $appsVersion = [Version]"$($settings.repoVersion).$([int]::MaxValue).$([int]::MaxValue)"
                $releasesJson = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
            
                try {
                    # version number counter includes draft or pre-release version numbers
                    $latestRelease = $releasesJson | Where-Object { ($appsVersion -gt [Version]$_.tag_name) } | Select-Object -First 1
                }
                catch {
                    OutputError -message "Error trying to locate previous release. Error was $($_.Exception.Message)"
                    exit
                }

                if ($latestRelease) {
                    try {
                        $latestVersion = [Version]$latestRelease.tag_name
                    }
                    catch {
                        OutputError -message "Using Versioning Strategy 2, releases must be tagged with the repo version number. Latest release was tagged $($latestRelease.tag_name)"
                        exit
                    }
                }
                else {
                    $latestVersion = [Version]"$($settings.repoVersion).0.0"
                }
                if ($release -eq "Y") {
                    $settings.appBuild = $latestVersion.Build + 1
                    $settings.appRevision = 0
                }
                else {
                    $settings.appBuild = $latestVersion.Build
                    $settings.appRevision = [Int32]($ENV:GITHUB_RUN_NUMBER)
                }
            }
            default {
                OutputError -message "Unknown version strategy $versionStrategy"
                exit
            }
        }
    }

    $outSettings = @{}
    $getSettings | ForEach-Object {
        $setting = $_.Trim()
        $outSettings += @{ "$setting" = $settings."$setting" }
        Add-Content -Path $env:GITHUB_ENV -Value "$setting=$($settings."$setting")"
    }
    $outSettingsJson = $outSettings | ConvertTo-Json -Compress
    Write-Host "::set-output name=Settings::$outSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"
}
catch {
    OutputError -message $_.Exception.Message
}