Param(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    [string] $baseFolder,
    [Parameter(HelpMessage = "The maximum depth to build the dependency tree", Mandatory = $false)]
    [int] $maxBuildDepth = 0,
    [Parameter(HelpMessage = "The GitHub token to use to fetch the modified files", Mandatory = $true)]
    [string] $token
)

#region Action: Setup
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper -baseFolder $baseFolder
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking
#endregion

$settings = $env:Settings | ConvertFrom-Json

$ghEventName = $ENV:GITHUB_EVENT_NAME
$branch = $env:GITHUB_REF_NAME
if ($ghEventName -eq 'pull_request') {
    $branch = $env:GITHUB_BASE_REF
    # DEPRECATION: REMOVE AFTER October 1st 2025 --->
    if ($settings.PSObject.Properties.Name -eq 'alwaysBuildAllProjects') {
        $buildAllProjects = $settings.alwaysBuildAllProjects
        Trace-DeprecationWarning -Message "alwaysBuildAllProjects is deprecated" -DeprecationTag "alwaysBuildAllProjects"
    }
    # <--- REMOVE AFTER October 1st 2025
    else {
        $buildAllProjects = !$settings.incrementalBuilds.onPullRequest
    }
}
else {
    # onPush, onSchedule or onWorkflow_Dispatch
    if ($settings.incrementalBuilds.PSObject.Properties.Name -eq "on$GhEventName") {
        $buildAllProjects = !$settings.incrementalBuilds."on$GhEventName"
    }
    else {
        $buildAllProjects = $true
    }
}
Write-Host "$ghEventName on $branch"

$baselineWorkflowRunId = 0 #default to 0, which means no baseline workflow run ID is set
$baselineWorkflowSHA = ''
if(-not $buildAllProjects) {
    Write-Host "::group::Determine Baseline Workflow ID"
    $baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $branch -token $token -retention $settings.incrementalBuilds.retentionDays
    Write-Host "::endgroup::"
}

#region Action: Determine projects to build
Write-Host "::group::Get Modified Files"
try {
    $modifiedFiles = @(Get-ModifiedFiles -baselineSHA $baselineWorkflowSHA)
    Write-Host "$($modifiedFiles.Count) modified file(s)"
    if ($modifiedFiles.Count -gt 0) {
        foreach($modifiedFile in $modifiedFiles) {
            Write-Host "- $modifiedFile"
        }
    }
}
catch {
    Write-Host "Failed to calculate modified files, building all projects"
    $buildAllProjects = $true
    $modifiedFiles = @()
}
Write-Host "::endgroup::"

Write-Host "::group::Determine Incremental Build"
$buildAllProjects = $buildAllProjects -or (Get-BuildAllProjects -modifiedFiles $modifiedFiles -baseFolder $baseFolder)
Write-Host "::endgroup::"

Write-Host "::group::Get Projects To Build"
$allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -buildAllProjects $buildAllProjects -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
Write-Host "::endgroup::"
#endregion

$skippedProjects = @($allProjects | Where-Object { $_ -notin $projectsToBuild })
if ($skippedProjects) {
    # If we are to publish artifacts for skipped projects later, we include the full project list and in the build step, just avoid building the skipped projects
    $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -buildAllProjects $true -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
}

#region Action: Output
$skippedProjectsJson = ConvertTo-Json -InputObject $skippedProjects -Depth 99 -Compress
$projectsJson = ConvertTo-Json $projectsToBuild -Depth 99 -Compress
$projectDependenciesJson = ConvertTo-Json $projectDependencies -Depth 99 -Compress
$buildOrderJson = ConvertTo-Json $buildOrder -Depth 99 -Compress

# Set output variables
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "SkippedProjectsJson=$skippedProjectsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ProjectsJson=$projectsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ProjectDependenciesJson=$projectDependenciesJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BuildOrderJson=$buildOrderJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BuildAllProjects=$([int] $buildAllProjects)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BaselineWorkflowRunId=$baselineWorkflowRunId"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BaselineWorkflowSHA=$baselineWorkflowSHA"

Write-Host "SkippedProjectsJson=$skippedProjectsJson"
Write-Host "ProjectsJson=$projectsJson"
Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
Write-Host "BuildOrderJson=$buildOrderJson"
Write-Host "BuildAllProjects=$buildAllProjects"
Write-Host "BaselineWorkflowRunId=$baselineWorkflowRunId"
Write-Host "BaselineWorkflowSHA=$baselineWorkflowSHA"
#endregion
