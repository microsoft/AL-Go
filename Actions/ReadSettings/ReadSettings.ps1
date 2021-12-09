Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Indicates whether this is called from a release pipeline", Mandatory = $false)]
    [string] $release = "N",
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    
    $telemetryScope = CreateScope -eventId 'DO0079' -parentTelemetryScopeJson $parentTelemetryScopeJson

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
            0 { # Use RUN_NUMBER and RUN_ATTEMPT
                $settings.appBuild = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
                $settings.appRevision = [Int32]($ENV:GITHUB_RUN_ATTEMPT) - 1
            }
            1 { # Use RUN_ID and RUN_ATTEMPT
                $settings.appBuild = [Int32]($ENV:GITHUB_RUN_ID)
                $settings.appRevision = [Int32]($ENV:GITHUB_RUN_ATTEMPT) - 1
            }
            2 { # USE DATETIME
                $settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
                $settings.appRevision = [Int32]([DateTime]::UtcNow.ToString('hhmmss'))
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

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    OutputError -message $_.Exception.Message
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}