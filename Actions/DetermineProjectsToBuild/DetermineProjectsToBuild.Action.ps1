Param(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    [string] $baseFolder,
    [Parameter(HelpMessage = "The maximum depth to build the dependency tree", Mandatory = $false)]
    [int] $maxBuildDepth = 0,
    [Parameter(HelpMessage = "Specifies whether to publish artifacts for skipped projects", Mandatory = $false)]
    [bool] $publishSkippedProjectArtifacts,
    [Parameter(HelpMessage = "The GitHub token to use to fetch the modified files", Mandatory = $true)]
    [string] $token
)

#region Action: Setup
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

DownloadAndImportBcContainerHelper -baseFolder $baseFolder
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking
#endregion

$settings = $env:Settings | ConvertFrom-Json

$ghEvent = Get-Content $env:GITHUB_EVENT_PATH -Encoding UTF8 | ConvertFrom-Json
if ($ghEvent.PSObject.Properties.name -eq 'pull_request') {
    # Pull request
    $buildAllProjects = $settings.alwaysBuildAllProjects
    $branch = $env:GITHUB_BASE_REF
    $publishSkippedProjectArtifacts = $false
    Write-Host "Pull request on $branch"
}
elseif ($ghEvent.PSObject.Properties.name -eq 'workflow_dispatch') {
    # Manual workflow dispatch
    $buildAllProjects = $true
    $branch = $env:GITHUB_REF_NAME
    $publishSkippedProjectArtifacts = $false
    Write-Host "Workflow dispatch on $branch"
}
else {
    # Push
    $buildAllProjects = !$settings.incrementalBuilds.enable

    $branch = $env:GITHUB_REF_NAME
    Write-Host "Push on $branch"
}
Write-Host "::group::Determine Baseline Workflow ID"
$baselineWorkflowRunId = 0 #default to 0, which means no baseline workflow run ID is set
$baselineWorkflowSHA = ''
if(-not $buildAllProjects) {
    $baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $branch -token $token
}
Write-Host "::endgroup::"

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

Write-Host "::group::Determine Partial Build"
$buildAllProjects = $buildAllProjects -or (Get-BuildAllProjects -modifiedFiles $modifiedFiles -baseFolder $baseFolder)
Write-Host "::endgroup::"


Write-Host "::group::Get Projects To Build"
$allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -buildAllProjects $buildAllProjects -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
Write-Host "::endgroup::"
#endregion

#region Action: Output
$skippedProjectsJson = ConvertTo-Json (@($allProjects | Where-Object { $_ -notin $projectsToBuild })) -Depth 99 -Compress
if ($publishSkippedProjectArtifacts) {
    # If we are to publish artifacts for skipped projects, we include the full project list and in the build step, just avoid building the skipped projects
    $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -buildAllProjects $true -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
}
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
