Param(
    [Parameter(Mandatory = $true)]
    [string] $repository,
    [Parameter(Mandatory = $true)]
    [string] $branch,
    [Parameter(Mandatory = $true)]
    [string] $token
)

<#
    Checks if all build jobs in a workflow run completed successfully.
#>
function CheckBuildJobsInWorkflowRun {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $api_url,
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $WorkflowRunId
    )

    $headers = GetHeader -token $token
    $per_page = 100
    $page = 1

    $allSuccessful = $true

    while($true) {
        $jobsURI = "$api_url/repos/$repository/actions/runs/$WorkflowRunId/jobs?per_page=$per_page&page=$page"
        Write-Host "- $jobsURI"
        $workflowJobs = InvokeWebRequest -Headers $headers -Uri $runsURI | ConvertFrom-Json

        if($workflowJobs.jobs.Count -eq 0) {
            # No more jobs, breaking out of the loop
            break
        }
        $buildJobs = @($workflowJobs.jobs | Where-Object { $_.name.StartsWith('Build ') })

        if($buildJobs.conclusion -ne 'success') {
            # If there is a build job that is not successful, there is not need to check further
            $allSuccessful = $false
        }

        if(-not $allSuccessful) {
            # there is a non-successful build job, no need to check further
            break
        }

        $page += 1
    }

    return $allSuccessful
}

<#
    Gets the last successful CICD run ID for the specified repository and branch.
    Successful CICD runs are those that have a workflow run named ' CI/CD' and successfully built all the projects.

    If no successful CICD run is found, 0 is returned.
#>
function FindLatestSuccessfulCICDRun {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $branch,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeader -token $token
    $lastSuccessfulCICDRun = 0
    $per_page = 100
    $page = 1

    Write-Host "Finding latest successful CICD run for branch $branch in repository $repository"

    # Get the latest CICD workflow run
    while($true) {
        $runsURI = "https://api.github.com/repos/$repository/actions/runs?per_page=$per_page&page=$page&exclude_pull_requests=true&status=completed&branch=$branch"
        Write-Host "- $runsURI"
        $workflowRuns = InvokeWebRequest -Headers $headers -Uri $runsURI | ConvertFrom-Json

        if($workflowRuns.workflow_runs.Count -eq 0) {
            # No more workflow runs, breaking out of the loop
            break
        }

        $CICDRuns = @($workflowRuns.workflow_runs | Where-Object { $_.name -eq ' CI/CD' })

        foreach($CICDRun in $CICDRuns) {
            if($CICDRun.conclusion -eq 'success') {
                # CICD run is successful
                $lastSuccessfulCICDRun = $CICDRun.id
                break
            }

            # CICD run is considered successful if all build jobs were successful
            $areBuildJobSuccessful = CheckBuildJobsInWorkflowRun -WorkflowRunId -$CICDRun.id -token $token -api_url $api_url -repository $repository

            if($areBuildJobSuccessful) {
                $lastSuccessfulCICDRun = $CICDRun.id
                break
            }

            Write-Host "CICD run $($CICDRun.id) is not successful. Skipping."
        }

        if($lastSuccessfulCICDRun -ne 0) {
            Write-Host "Found last successful CICD run: $($lastSuccessfulCICDRun)"
            break
        }

        $page += 1
    }

    if($lastSuccessfulCICDRun -eq 0) {
        Write-Host "No successful CICD run found for branch $branch in repository $repository"
    }

    return $lastSuccessfulCICDRun
}

$workflowRunID = FindLatestSuccessfulCICDRun -token $token -api_url $api_url -repository $repository -branch $ENV:GITHUB_BASE_REF

# Set output variables
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "WorkflowRunID=$workflowRunID"