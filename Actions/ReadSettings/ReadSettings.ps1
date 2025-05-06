Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Build mode", Mandatory = $false)]
    [string] $buildMode = "Default",
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = "",
    [Parameter(HelpMessage = "Current environment name", Mandatory = $false)]
    [string] $environmentName = "",
    [Parameter(HelpMessage = "Environment deploy to variable", Mandatory = $false)]
    [string] $environmentDeployToVariableValue = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = ReadSettings -project $project -buildMode $buildMode -environmentName $environmentName -environmentDeployToVariableValue $environmentDeployToVariableValue -token $token
if ($get) {
    $getSettings = $get.Split(',').Trim()
}
else {
    $getSettings = @()
}

if ($ENV:GITHUB_EVENT_NAME -in @("pull_request_target", "pull_request")) {
    $settings.doNotSignApps = $true
    $settings.versioningStrategy = 15
}

if ($settings.appBuild -eq [int32]::MaxValue) {
    $settings.versioningStrategy = 15
}

if ($settings.versioningstrategy -ne -1) {
    switch ($settings.versioningStrategy -band 15) {
        0 { # Use RUN_NUMBER and RUN_ATTEMPT
            $settings.appBuild = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
            $settings.appRevision = [Int32]($ENV:GITHUB_RUN_ATTEMPT) - 1
        }
        1 { # Use RUN_ID and RUN_ATTEMPT
            OutputError -message "Versioning strategy 1 is no longer supported"
        }
        2 { # USE DATETIME
            $settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
            $settings.appRevision = [Int32]([DateTime]::UtcNow.ToString('HHmmss'))
        }
        3 { # USE BUIlD from app.json and RUN_NUMBER
            $settings.appBuild = -1
            $settings.appRevision = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
        }
        15 { # Use maxValue and RUN_NUMBER
            $settings.appBuild = [Int32]::MaxValue
            $settings.appRevision = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
        }
        default {
            OutputError -message "Unknown versioning strategy $($settings.versioningStrategy)"
            exit
        }
    }
}

$outSettings = @{}
$settings.Keys | ForEach-Object {
    $setting = $_
    $settingValue = $settings."$setting"
    if ($settingValue -is [String] -and ($settingValue.contains("`n") -or $settingValue.contains("`r"))) {
        throw "Setting $setting contains line breaks, which is not supported"
    }
    $outSettings += @{ "$setting" = $settingValue }
    if ($getSettings -contains $setting) {
        if ($settingValue -is [System.Collections.Specialized.OrderedDictionary] -or $settingValue -is [hashtable]) {
            Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "$setting=$(ConvertTo-Json $settingValue -Depth 99 -Compress)"
        }
        else {
            Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "$setting=$settingValue"
        }
    }
}

Write-Host "SETTINGS:"
$outSettings | ConvertTo-Json -Depth 99 | Out-Host
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "Settings=$($outSettings | ConvertTo-Json -Depth 99 -Compress)"

$gitHubRunner = $settings.githubRunner.Split(',').Trim() | ConvertTo-Json -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "GitHubRunnerJson=$githubRunner"
Write-Host "GitHubRunnerJson=$githubRunner"

$gitHubRunnerShell = $settings.githubRunnerShell
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "GitHubRunnerShell=$githubRunnerShell"
Write-Host "GitHubRunnerShell=$githubRunnerShell"
