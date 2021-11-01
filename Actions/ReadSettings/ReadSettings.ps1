Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Indicates whether this is called from a release pipeline", Mandatory = $false)]
    [string] $release = "N",
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    if ($project  -eq ".") { $project = "" }
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
   
    $settings = ReadSettings -baseFolder $baseFolder -workflowName $env:GITHUB_WORKFLOW
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    if ($getSettings -contains 'appBuild' -or $getSettings -contains 'appRevision') {
        switch ($settings.versioningStrategy -band 15) {
            0 { # Use RUNID
                $settings.appBuild = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
                $settings.appRevision = 0
            }
            1 { # USE DATETIME
                $settings.appBuild = [Int32]([DateTime]::Now.ToString('yyyyMMdd'))
                $settings.appRevision = [Int32]([DateTime]::Now.ToString('hhmmss'))
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
    Write-Host "::set-output name=SettingsJson::$outSettingsJson"
    Write-Host "set-output name=SettingsJson::$outSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"
}
catch {
    OutputError -message $_.Exception.Message
}