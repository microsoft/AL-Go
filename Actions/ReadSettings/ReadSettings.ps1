Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Indicates whether you want to retrieve the list of project list as well", Mandatory = $false)]
    [bool] $getprojects,
    [Parameter(HelpMessage = "Specify the pattern of the environments you want to retreive (or empty for no environments)", Mandatory = $false)]
    [string] $getenvironments = "",
    [Parameter(HelpMessage = "Specify whether you want to include production environments", Mandatory = $false)]
    [bool] $includeProduction,
    [Parameter(HelpMessage = "Indicates whether this is called from a release pipeline", Mandatory = $false)]
    [bool] $release,
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

    $gitHubRunner = $settings.githubRunner.Split(',') | ConvertTo-Json -compress
    Write-Host "::set-output name=GitHubRunnerJson::$githubRunner"
    Write-Host "set-output name=GitHubRunnerJson::$githubRunner"

    if ($getprojects) {
        if (Test-Path ".AL-Go" -PathType Container) {
            $projects = @(".")
        }
        else {
            $projects = @(Get-ChildItem -Path $ENV:GITHUB_WORKSPACE -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".AL-Go") -PathType Container } | ForEach-Object { $_.Name })
            Write-Host "All Projects: $($projects -join ', ')"
            if (($ENV:GITHUB_EVENT_NAME -eq "pull_request" -or $ENV:GITHUB_EVENT_NAME -eq "push") -and !$settings.alwaysBuildAllProjects) {
                $headers = @{             
                    "Authorization" = "token $token"
                    "Accept" = "application/vnd.github.baptiste-preview+json"
                }
                $ghEvent = Get-Content $ENV:GITHUB_EVENT_PATH -encoding UTF8 | ConvertFrom-Json
                if ($ENV:GITHUB_EVENT_NAME -eq "pull_request") {
                    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/compare/$($ghEvent.pull_request.base.sha)...$($ENV:GITHUB_SHA)"
                }
                else {
                    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/compare/$($ghEvent.before)...$($ghEvent.after)"
                }
                $response = Invoke-WebRequest -Headers $headers -UseBasicParsing -Method GET -Uri $url | ConvertFrom-Json
                $filesChanged = @($response.files | ForEach-Object { $_.filename })
                if ($filesChanged.Count -lt 250) {
                    $foldersChanged = @($filesChanged | ForEach-Object { $_.Split('/')[0] } | Select-Object -Unique)
                    $projects = @($projects | Where-Object { $foldersChanged -contains $_ })
                    Write-Host "Modified projects: $($projects -join ', ')"
                }
            }
        }
        if ($projects.Count -eq 1) {
            $projectsJSon = "[$($projects | ConvertTo-Json -compress)]"
        }
        else {
            $projectsJSon = $projects | ConvertTo-Json -compress
        }
        Write-Host "::set-output name=ProjectsJson::$projectsJson"
        Write-Host "set-output name=ProjectsJson::$projectsJson"
        Write-Host "::set-output name=ProjectCount::$($projects.Count)"
        Write-Host "set-output name=ProjectCount::$($projects.Count)"
        Add-Content -Path $env:GITHUB_ENV -Value "Projects=$projectsJson"
    }

    if ($getenvironments) {
        $headers = @{ 
            "Authorization" = "token $token"
            "Accept"        = "application/vnd.github.v3+json"
        }
        $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"
        try {
            $environments = @((Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url | ConvertFrom-Json).environments | Where-Object { 
                if ($includeProduction) {
                    $_.Name -like $getEnvironments -or $_.Name -like "$getEnvironments (Production)"
                }
                else {
                    $_.Name -like $getEnvironments -and $_.Name -notlike '* (Production)'
                }
            } | ForEach-Object { $_.Name })
        }
        catch {
            $environments = @()
        }
        if ($environments.Count -eq 1) {
            $environmentsJSon = "[$($environments | ConvertTo-Json -compress)]"
        }
        else {
            $environmentsJSon = $environments | ConvertTo-Json -compress
        }
        Write-Host "::set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "::set-output name=EnvironmentCount::$($environments.Count)"
        Write-Host "set-output name=EnvironmentCount::$($environments.Count)"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }

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
