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

$ghEvent = Get-Content $env:GITHUB_EVENT_PATH -Encoding UTF8 | ConvertFrom-Json
if ($ghEvent.PSObject.Properties.name -eq 'pull_request') {
    $buildAllProjects = $settings.alwaysBuildAllProjects
    $branch = $env:GITHUB_BASE_REF
}
else {
    $buildAllProjects = !$settings.partialBuilds.enabled
    $branch = $env:GITHUB_REF_NAME
}
Write-Host "::group::Determine Baseline Workflow ID $branch"
$baselineWorkflowRunId = 0 #default to 0, which means no baseline workflow run ID is set
$baselineWorkflowSHA = ''
if(-not $buildAllProjects) {
    $baselineWorkflowRunId,$baselineWorkflowSHA = FindLatestSuccessfulCICDRun -repository $env:GITHUB_REPOSITORY -branch $branch -token $token
}
Write-Host "::endgroup::"

#region Action: Determine projects to build
Write-Host "::group::Get Modified Files"
$modifiedFiles = @(Get-ModifiedFiles -token $token -baselineSHA $baselineWorkflowSHA)
Write-Host "$($modifiedFiles.Count) modified file(s)"
if ($modifiedFiles.Count -gt 0) {
    foreach($modifiedFile in $modifiedFiles) {
        Write-Host "- $modifiedFile"
    }
}
Write-Host "::endgroup::"

Write-Host "::group::Determine Partial Build"
$buildAllProjects = Get-BuildAllProjects -modifiedFiles $modifiedFiles -baseFolder $baseFolder
Write-Host "::endgroup::"


Write-Host "::group::Get Projects To Build"
$allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -buildAllProjects $buildAllProjects -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
Write-Host "::endgroup::"
#endregion

#region Action: Output
$projectsJson = ConvertTo-Json $projectsToBuild -Depth 99 -Compress
$projectDependenciesJson = ConvertTo-Json $projectDependencies -Depth 99 -Compress
$buildOrderJson = ConvertTo-Json $buildOrder -Depth 99 -Compress

# Set output variables
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ProjectsJson=$projectsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ProjectDependenciesJson=$projectDependenciesJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BuildOrderJson=$buildOrderJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BuildAllProjects=$([int] $buildAllProjects)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BaselineWorkflowRunId=$baselineWorkflowRunId"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BaselineWorkflowSHA=$baselineWorkflowSHA"


Write-Host "ProjectsJson=$projectsJson"
Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
Write-Host "BuildOrderJson=$buildOrderJson"
Write-Host "BuildAllProjects=$buildAllProjects"
Write-Host "BaselineWorkflowRunId=$baselineWorkflowRunId"
Write-Host "BaselineWorkflowSHA=$baselineWorkflowSHA"
#endregion
