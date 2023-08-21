param(
    [Parameter(Mandatory = $true)]
    [string] $Repository,
    [Parameter(Mandatory = $true)]
    [string] $RunId
)

Write-Host "Checking workflow status for run $RunId in repository $Repository"

$workflowJobs = gh api /repos/$Repository/actions/runs/$RunId/jobs | ConvertFrom-Json
$failedJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" }

if ($failedJobs) {
    throw "Workflow failed with the following jobs: $($failedJobs.name -join ', ')"
}

Write-Host "Workflow succeeded"