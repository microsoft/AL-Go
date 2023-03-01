Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

function Get-ChangedFiles($token) {
    $headers = @{             
        "Authorization" = "token $token"
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }
    $ghEvent = Get-Content $env:GITHUB_EVENT_PATH -encoding UTF8 | ConvertFrom-Json

    $url = "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)/compare/$($ghEvent.pull_request.base.sha)...$($ghEvent.pull_request.head.sha)"

    $response = InvokeWebRequest -Headers $headers -Uri $url | ConvertFrom-Json
    $filesChanged = @($response.files | ForEach-Object { $_.filename })

    return $filesChanged
}

function Get-ProjectsToBuild($settings, $projects, $baseFolder, $token) {
    if ($settings.alwaysBuildAllProjects) {
        Write-Host "Building all projects because alwaysBuildAllProjects is set to true"
        return $projects
    } 
    
    if ($env:GITHUB_EVENT_NAME -notin @("pull_request_target", "pull_request")) {
        Write-Host "Building all projects because this is not a pull request"
        return $projects
    }

    $filesChanged = @(Get-ChangedFiles -token $token)
    if ($filesChanged -like '.github/*.json') {
        Write-Host "Changes to repo Settings, building all projects"
        return $projects
    }
    elseif ($filesChanged.Count -ge 250) {
        Write-Host "More than 250 files modified, building all projects"
        return $projects
    }
    else {
        Write-Host "Modified files:"
        $buildProjects = @()
        $filesChanged | Out-Host
        $buildProjects = @($projects | Where-Object {
                $checkProject = $_
                $buildProject = $false
                if (Test-Path -Path (Join-Path $baseFolder "$checkProject/.AL-Go/settings.json")) {
                    $projectFolders = Get-ProjectFolders -baseFolder $baseFolder -project $checkProject -token $token -includeAlGoFolder -includeApps -includeTestApps
                    $projectFolders | ForEach-Object {
                        if ($filesChanged -like "$_/*") { $buildProject = $true }
                    }
                }
                $buildProject
            })
        return $buildProjects
    }
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    $baseFolder = $env:GITHUB_WORKSPACE
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $bcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking
    $telemetryScope = CreateScope -eventId 'DO0079' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $settings = ReadSettings -baseFolder $baseFolder -project '.' # Load AL-Go settings for the repo

    Write-Host "Determining projects to build"
    if ($settings.projects) {
        Write-Host "Projects specified in settings"
        
        $projects = $settings.projects
    }
    else {
        # Get all projects that have a settings.json file
        $projects = @(Get-ChildItem -Path $baseFolder -Recurse -Depth 2 | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName ".AL-Go/settings.json") -PathType Leaf) } | ForEach-Object { $_.FullName.Substring($baseFolder.length+1) })
        
        # If the repo has a settings.json file, add it to the list of projects to build
        if (Test-Path (Join-Path ".AL-Go" "settings.json") -PathType Leaf) {
            $projects += @(".")
        }
    }
    
    Write-Host "Found AL-Go Projects: $($projects -join ', ')"
    
    $buildProjects = @()
    $projectDependencies = @{}
    $buildOrder = @()
    
    if ($projects) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "projects" -value "$($projects -join ', ')"
        
        $buildProjects += Get-ProjectsToBuild -settings $settings -projects $projects -baseFolder $baseFolder -token $token
        
        $buildAlso = @{}
        $buildOrder = AnalyzeProjectDependencies -baseFolder $baseFolder -projects $projects -buildAlso ([ref]$buildAlso) -projectDependencies ([ref]$projectDependencies)
        
        $buildProjects = @($buildProjects | ForEach-Object { $_; if ($buildAlso.Keys -contains $_) { $buildAlso."$_" } } | Select-Object -Unique)
    }
    
    Write-Host "Projects to build: $($buildProjects -join ', ')"
    
    $projectsJson = ConvertTo-Json $buildProjects -Depth 99 -Compress
    $projectDependenciesJson = ConvertTo-Json $projectDependencies -Depth 99 -Compress
    $buildOrderJson = ConvertTo-Json $buildOrder -Depth 99 -Compress
    
    # Set output variables
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectsJson=$projectsJson"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectDependenciesJson=$projectDependenciesJson"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "BuildOrderJson=$buildOrderJson"    
    
    Write-Host "ProjectsJson=$projectsJson"
    Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
    Write-Host "BuildOrderJson=$buildOrderJson"

}
catch {
    OutputError -message "LoadProjects action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
    
