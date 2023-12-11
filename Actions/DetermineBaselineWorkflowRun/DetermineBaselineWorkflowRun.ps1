Param(
    [Parameter(Mandatory = $true)]
    [string] $repository,
    [Parameter(Mandatory = $true)]
    [string] $branch,
    [Parameter(Mandatory = $true)]
    [string] $token
)

Import-Module (Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve)

$workflowRunID = FindLatestSuccessfulCICDRun -token $token -repository $repository -branch $branch

# Set output variables
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "WorkflowRunID=$workflowRunID"