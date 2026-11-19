. (Join-Path $PSScriptRoot '..\AL-Go-Helper.ps1' -Resolve)

<#
.SYNOPSIS
    Checks a Pull Request build run and fails if any required job failed.
.DESCRIPTION
    Queries the GitHub Actions jobs API and throws for required jobs concluded with "failure".
    Jobs named "Build * (*) / * (*)" matching optional wildcard patterns emit warnings instead.
    Other jobs remain required. Other conclusions retain their existing behavior.
    Writes failedOptionalJobs as a JSON array of failed optional job names before reporting required failures.
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
.PARAMETER OptionalPatterns
    Case-insensitive PowerShell wildcard patterns matching full build job names.
.EXAMPLE
    PullRequestStatusCheck -Repository "owner/repo" -RunId "123456"
#>
function PullRequestStatusCheck() {
    param(
        [Parameter(HelpMessage = "Repository name", Mandatory = $true)]
        [string] $Repository,
        [Parameter(HelpMessage = "Run Id", Mandatory = $true)]
        [string] $RunId,
        [string[]] $OptionalPatterns = @()
    )
    Write-Host "Checking PR Build status for run $RunId in repository $Repository"

    foreach ($pattern in $OptionalPatterns) {
        # Fail-Fast for invalid wildcard patterns. Force wildcard parsing even when the run contains no failed jobs.
        $null = '' -like $pattern
    }
    $env:GH_HOST = ([Uri]$env:GITHUB_SERVER_URL).Host
    $workflowJobs = Invoke-CommandWithRetry -RetryCount 5 -FirstDelay 5 -MaxWaitBetweenRetries 60 -ScriptBlock {
        $jobsJson = gh api "/repos/$Repository/actions/runs/$RunId/jobs?per_page=50" --paginate --slurp -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28"
        if ($LASTEXITCODE) {
            throw "Failed to get jobs for run $RunId in repository $Repository (gh exit code $LASTEXITCODE)."
        }
        $jobsJson | ConvertFrom-Json | ForEach-Object {
            foreach ($page in $_) {
                $page | ConvertTo-HashTable -recurse
            }
        }
    }

    # --slurp yields an array with one entry per page; member enumeration flattens jobs across all pages.
    # When a single (non-slurped) object is returned, .jobs resolves to that object's jobs.
    $failedJobs = @($workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" })

    $failedOptionalJobs = @()
    $badFailures = @(
        foreach ($job in $failedJobs) {
            $matchesOptionalPattern = @($OptionalPatterns | Where-Object { $job.name -like $_ }).Count -gt 0
            if ($job.name -like 'Build * (*) / * (*)' -and $matchesOptionalPattern) {
                $failedOptionalJobs += $job.name
                OutputWarning -message "Optional PR build job failed (non-blocking): $($job.name)"
                continue
            }
            $job
        }
    )
    $failedOptionalJobsJson = ConvertTo-Json -InputObject $failedOptionalJobs -Compress
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "failedOptionalJobs=$failedOptionalJobsJson"
    if ($badFailures) {
        throw "PR Build failed. Failing jobs: $($badFailures.name -join ', ')"
    }
}

if (!$env:Settings) {
    throw "Settings environment variable is required."
}
$settingsJson = $env:Settings | ConvertFrom-Json
$rawOptionalPatterns = $settingsJson.optionalPatternsForPrValidation
if ($rawOptionalPatterns -isnot [System.Array]) {
    throw "Settings.optionalPatternsForPrValidation must be an array."
}
foreach ($pattern in $rawOptionalPatterns) {
    if ($pattern -isnot [string]) {
        throw "Settings.optionalPatternsForPrValidation must contain only strings."
    }
}
$settings = $settingsJson | ConvertTo-HashTable -recurse
$optionalPatterns = @($settings.optionalPatternsForPrValidation)
PullRequestStatusCheck -Repository $env:GITHUB_REPOSITORY -RunId $env:GITHUB_RUN_ID -OptionalPatterns $optionalPatterns
Write-Host "PR Build succeeded"
