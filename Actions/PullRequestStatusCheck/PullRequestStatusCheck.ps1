param(
    [Parameter(Mandatory = $true)]
    [string] $Repository,
    [Parameter(Mandatory = $true)]
    [string] $RunId
)

Write-Host "gh api /repos/$Repository/actions/runs/$RunId/jobs"
$workflowJobs = gh api /repos/$Repository/actions/runs/$RunId/jobs | ConvertFrom-Json
$failedJobs = $workflowJobs | Where-Object { $_.conclusion -eq "failure" }

if ($failedJobs) {
    throw "Workflow failed with the following jobs: $($failedJobs.name -join ', ')"
}
