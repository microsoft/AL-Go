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

$targetBranch = $env:GITHUB_REF_NAME
if ($ENV:GITHUB_EVENT_NAME -eq 'pull_request') {
    $targetBranch = $env:GITHUB_BASE_REF
}

#region Action: Determine projects to build
Write-Host "$($ENV:GITHUB_EVENT_NAME) on $targetBranch"
$buildAllProjects, $publishSkippedProjects = Get-BuildAllProjectsBasedOnEventAndSettings -ghEventName $ENV:GITHUB_EVENT_NAME -settings $settings

$modifiedFiles = @()
$baselineWorkflowRunId = 0 #default to 0, which means no baseline workflow run ID is set
$baselineWorkflowSHA = ''
if(-not $buildAllProjects) {
    Write-Host "::group::Determine Baseline Workflow ID"
    $baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $targetBranch -token $token -retention $settings.incrementalBuilds.retentionDays
    Write-Host "::endgroup::"

    Write-Host "::group::Get Modified Files"
    try {
        $buildAllProjects, $modifiedFiles = Get-ModifiedFiles -baselineSHA $baselineWorkflowSHA
        OutputMessageAndArray -message "Modified files" -arrayOfStrings $modifiedFiles
    }
    catch {
        OutputNotice -message "Failed to calculate modified files since $baselineWorkflowSHA, building all projects"
        $buildAllProjects = $true
    }
    Write-Host "::endgroup::"
}

if (-not $buildAllProjects) {
    Write-Host "::group::Determine Incremental Build"
    $buildAllProjects = Get-BuildAllProjects -modifiedFiles $modifiedFiles -baseFolder $baseFolder
    Write-Host "::endgroup::"
}

# If we are to publish artifacts for skipped projects later, we include the full project list and in the build step, just avoid building the skipped projects
# buildAllProjects is set to true if we are to build all projects
# publishSkippedProjects is set to true if we are to publish artifacts for skipped projects (meaning we are still going through the build process for all projects, just not building)
Write-Host "::group::Get Projects To Build"
$allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -buildAllProjects ($buildAllProjects -or $publishSkippedProjects) -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
if ($buildAllProjects) {
    $skippedProjects = @()
}
else {
    $skippedProjects = @($allProjects | Where-Object { $_ -notin $modifiedProjects })
}
Write-Host "::endgroup::"
#endregion

#region Action: Output
$skippedProjectsJson = ConvertTo-Json -InputObject $skippedProjects -Depth 99 -Compress
$projectsJson = ConvertTo-Json $projectsToBuild -Depth 99 -Compress
$projectDependenciesJson = ConvertTo-Json $projectDependencies -Depth 99 -Compress
$buildOrderJson = ConvertTo-Json $buildOrder -Depth 99 -Compress

$additionalDataForTelemetry = [System.Collections.Generic.Dictionary[[System.String], [System.String]]]::new()
$additionalDataForTelemetry.Add("Mode", $settings.incrementalBuilds.Mode)
$additionalDataForTelemetry.Add("Event", $ENV:GITHUB_EVENT_NAME)
$additionalDataForTelemetry.Add("Projects", $allProjects.Count)
$additionalDataForTelemetry.Add("ModifiedProjects", $modifiedProjects.Count)
$additionalDataForTelemetry.Add("ProjectsToBuild", $projectsToBuild.Count)

Trace-Information -Message "Incremental builds (projects)" -AdditionalData $additionalDataForTelemetry

# Add annotation for last known good build
if ($baselineWorkflowRunId) {
    Write-Host "::notice::Last known good build: https://github.com/$($env:GITHUB_REPOSITORY)/actions/runs/$baselineWorkflowRunId"
}

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
