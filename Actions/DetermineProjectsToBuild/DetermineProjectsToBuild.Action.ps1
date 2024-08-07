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

#region Action: Determine projects to build
Write-Host "::group::Get Modified Files"
$modifiedFiles = @(Get-ModifiedFiles -token $token)
Write-Host "$($modifiedFiles.Count) modified file(s): $($modifiedFiles -join ', ')"
Write-Host "::endgroup::"

Write-Host "::group::Determine Partial Build"
$buildAllProjects = Get-BuildAllProjects -modifiedFiles $modifiedFiles -baseFolder $baseFolder
Write-Host "::endgroup::"

Write-Host "::group::Determine Baseline Workflow ID"
$baselineWorkflowRunId = 0 #default to 0, which means no baseline workflow run ID is set
if(-not $buildAllProjects) {
    $baselineWorkflowRunId = FindLatestSuccessfulCICDRun -repository "$env:GITHUB_REPOSITORY" -branch "$env:GITHUB_BASE_REF" -token $token
}
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


Write-Host "ProjectsJson=$projectsJson"
Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
Write-Host "BuildOrderJson=$buildOrderJson"
Write-Host "BuildAllProjects=$buildAllProjects"
Write-Host "BaselineWorkflowRunId=$baselineWorkflowRunId"
#endregion
