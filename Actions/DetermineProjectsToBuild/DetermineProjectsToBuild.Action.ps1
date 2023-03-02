Param(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    [string] $baseFolder,
    [Parameter(HelpMessage = "An array of changed files paths, used to filter the projects to build", Mandatory = $false)]
    [string[]] $modifiedFiles = @(),

    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    #region Action: Setup
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $bcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking
    #endregion
    
    #region Action: Determine projects to build
    . (Join-Path -Path $PSScriptRoot -ChildPath "DetermineProjectsToBuild.ps1" -Resolve)
    $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles
    
    $telemetryScope = CreateScope -eventId 'DO0079' -parentTelemetryScopeJson $parentTelemetryScopeJson
    AddTelemetryProperty -telemetryScope $telemetryScope -key "projects" -value "$($allProjects -join ', ')"
    #endregion

    #region Action: Output
    $projectsJson = ConvertTo-Json $projectsToBuild -Depth 99 -Compress
    $projectDependenciesJson = ConvertTo-Json $projectDependencies -Depth 99 -Compress
    $buildOrderJson = ConvertTo-Json $buildOrder -Depth 99 -Compress
    
    # Set output variables
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectsJson=$projectsJson"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectDependenciesJson=$projectDependenciesJson"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "BuildOrderJson=$buildOrderJson"    
    
    Write-Host "ProjectsJson=$projectsJson"
    Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
    Write-Host "BuildOrderJson=$buildOrderJson"
    #endregion
}
catch {
    OutputError -message "DetermineProjectsToBuild action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
    
