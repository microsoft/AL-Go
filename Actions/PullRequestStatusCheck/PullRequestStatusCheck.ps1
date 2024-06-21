function PullRequestStatusCheck()
{
    param(
        [Parameter(HelpMessage = "Repository name", Mandatory = $true)]
        [string] $Repository,
        [Parameter(HelpMessage = "Run Id", Mandatory = $true)]
        [string] $RunId
    )
    Write-Host "Checking PR Build status for run $RunId in repository $Repository"

    $workflowJobs = gh api /repos/$Repository/actions/runs/$RunId/jobs -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json
    $failedJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" }

    if ($failedJobs) {
        throw "PR Build failed. Failing jobs: $($failedJobs.name -join ', ')"
    }
}

PullRequestStatusCheck -Repository $env:GITHUB_REPOSITORY -RunId $env:GITHUB_RUN_ID
Write-Host "PR Build succeeded"
