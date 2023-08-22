param(
    [Parameter(HelpMessage = "Repository name", Mandatory = $false)]
    [string] $Repository,
    [Parameter(HelpMessage = "Run Id", Mandatory = $false)]
    [string] $RunId
)

Write-Host "Checking PR Build status for run $RunId in repository $Repository"

$workflowJobs = gh api /repos/$Repository/actions/runs/$RunId/jobs -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json
$failedJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" }

if ($failedJobs) {
    throw "PR Build failed. Failing jobs: $($failedJobs.name -join ', ')"
}

Write-Host "PR Build succeeded"