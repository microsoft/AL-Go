Param(
    [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
    [string] $prBaseRepository,
    [Parameter(HelpMessage = "The id of the pull request", Mandatory = $false)]
    [string] $pullRequestId
)

function ValidateFiles
(
    [Object[]] $Files
) {
    $disallowedExtensions = @('.ps1', '.psm1', '.yml', '.yaml')
    $disallowedFiles = @('CODEOWNERS')

    $Files | ForEach-Object {
        $filename = $_.filename
        $status = $_.status
        Write-Host "- $filename $status"
        $extension = [System.IO.Path]::GetExtension($filename)
        $name = [System.IO.Path]::GetFileName($filename)
        if (($extension -in $disallowedExtensions) -or ($name -in $disallowedFiles) -or $filename.StartsWith(".github/")) {
            throw "Pull Request containing changes to scripts, workflows or CODEOWNERS are not allowed from forks."
        }
    }
}

function ValidatePullRequest
(
    [string[]] $PullRequestRepository,
    [string[]] $PullRequestId,
    [hashtable] $Headers,
    [int] $MaxAllowedChangedFiles = 3000
) {
    $url = "https://api.github.com/repos/$($prBaseRepository)/pulls/$pullRequestId"
    $pullRequestDetails = Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri $url | ConvertFrom-Json

    # List Pull Request files has a max of 3000 files. https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#list-pull-requests-files
    if ($pullRequestDetails.changed_files -gt $MaxAllowedChangedFiles) {
        throw "Pull request contains changes to $($pullRequestDetails.changed_files) files. You cannot change more than $MaxAllowedChangedFiles files from a fork."
    }
}

function ValidatePullRequestFiles
(
    [string[]] $PullRequestRepository,
    [string[]] $PullRequestId,
    [hashtable] $Headers
) {
    $pageNumber = 1
    $resultsPerPage = 100
    $hasMoreData = $true
    Write-Host "Files Changed:"
    while ($hasMoreData) {
        $url = "https://api.github.com/repos/$($prBaseRepository)/pulls/$pullRequestId/files?per_page=$resultsPerPage&page=$pageNumber"
        $changedFiles = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url | ConvertFrom-Json

        # Finish check if there are no more files to be validated
        if (-not $changedFiles) {
            break
        }

        ValidateFiles -Files $changedFiles

        if ($changedFiles -and ($changedFiles.Count -eq $resultsPerPage)) {
            $pageNumber += 1
        }
        else {
            $hasMoreData = $false
        }
    }
    Write-Host "Verification completed successfully."
}

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch
# IMPORTANT: All actions needs a try/catch here and not only in the yaml file, else they can silently fail

try {
    $headers = @{
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.baptiste-preview+json"
    }

    ValidatePullRequest -PullRequestRepository $prBaseRepository -PullRequestId $pullRequestId -Headers $headers
    ValidatePullRequestFiles -PullRequestRepository $prBaseRepository -PullRequestId $pullRequestId -Headers $headers
}
catch {
    Write-Host "::ERROR::VerifyPRChanges action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    $host.SetShouldExit(1)
    throw
}
