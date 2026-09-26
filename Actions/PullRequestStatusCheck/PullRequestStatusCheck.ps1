$gitHubHelperPath = Join-Path $PSScriptRoot '..\Github-Helper.psm1' -Resolve
Import-Module $gitHubHelperPath -DisableNameChecking

<#
.SYNOPSIS
    Checks the status of all jobs in a Pull Request build run and fails if any job failed.
.DESCRIPTION
    Queries the GitHub Actions jobs API for the given run and throws if any job concluded with "failure".
    The jobs endpoint is paginated and can return a large response for builds with many jobs (for example
    a build that spans many countries). Three robustness measures are applied:
    - The request is retried, because the (large) jobs endpoint intermittently returns HTTP 502.
    - A smaller page size (per_page) is requested so each page is faster to generate server-side, which
      reduces the chance of a gateway timeout (HTTP 502).
    - "--slurp" is used so that multi-page responses are returned as a single JSON array. Without it,
      "gh api --paginate" concatenates one JSON object per page, which ConvertFrom-Json cannot parse
      (it fails with "Invalid JSON primitive").
.PARAMETER Repository
    The repository (owner/name) that owns the run.
.PARAMETER RunId
    The id of the workflow run to check.
.EXAMPLE
    PullRequestStatusCheck -Repository "owner/repo" -RunId "123456"
#>
function PullRequestStatusCheck()
{
    param(
        [Parameter(HelpMessage = "Repository name", Mandatory = $true)]
        [string] $Repository,
        [Parameter(HelpMessage = "Run Id", Mandatory = $true)]
        [string] $RunId
    )
    Write-Host "Checking PR Build status for run $RunId in repository $Repository"

    $workflowJobs = Invoke-CommandWithRetry -RetryCount 5 -FirstDelay 5 -MaxWaitBetweenRetries 60 -ScriptBlock {
        $env:GH_HOST = ([Uri]$env:GITHUB_SERVER_URL).Host
        $jobsJson = gh api "/repos/$Repository/actions/runs/$RunId/jobs?per_page=50" --paginate --slurp -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28"
        if ($LASTEXITCODE) {
            throw "Failed to get jobs for run $RunId in repository $Repository (gh exit code $LASTEXITCODE)."
        }
        $jobsJson | ConvertFrom-Json
    }

    # --slurp yields an array with one entry per page; member enumeration flattens jobs across all pages.
    # When a single (non-slurped) object is returned, .jobs resolves to that object's jobs.
    $failedJobs = @($workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" })

    if ($failedJobs) {
        throw "PR Build failed. Failing jobs: $($failedJobs.name -join ', ')"
    }
}

PullRequestStatusCheck -Repository $env:GITHUB_REPOSITORY -RunId $env:GITHUB_RUN_ID
Write-Host "PR Build succeeded"
