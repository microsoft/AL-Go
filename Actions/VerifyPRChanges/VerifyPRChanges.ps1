Param(
  [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
  [string] $token,
  [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $false)]
  [string] $baseSHA,
  [Parameter(HelpMessage = "Head commit of the PR", Mandatory = $false)]
  [string] $headSHA,
  [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
  [string] $prBaseRepository,
  [Parameter(HelpMessage = "The id of the pull request", Mandatory = $false)]
  [string] $pullRequestId
)

function ValidateFiles
(
  [Object[]] $Files
)
{
  $Files | ForEach-Object {
    $filename = $_.filename
    $status = $_.status
    Write-Host "- $filename $status"
    $extension = [System.IO.Path]::GetExtension($filename)
    $name = [System.IO.Path]::GetFileName($filename)
    if ($extension -eq '.ps1' -or $extension -eq '.yaml' -or $extension -eq '.yml' -or $name -eq "CODEOWNERS" -or $filename.StartsWith(".github/")) {
      throw "Pull Request containing changes to scripts, workflows or CODEOWNERS are not allowed from forks."
    }
  } 
}

function ValidatePullRequest
(
  [string[]] $PullRequestRepository,
  [string[]] $PullRequestId,
  [object] $Headers
)
{
  $url = "https://api.github.com/repos/$($prBaseRepository)/pulls/$pullRequestId"
  $pullRequestDetails = Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri $url | ConvertFrom-Json

  #List Pull Request files has a max of 3000 files. https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#list-pull-requests-files
  if ($pullRequestDetails.changed_files -gt 3000) {
    throw "Pull request contains changes to $($pullRequestDetails.changed_files) files. You cannot change more than 1000 files from a fork."
  }
}

function ValidatePullRequestFiles
(
  [string[]] $PullRequestRepository,
  [string[]] $PullRequestId,
  [object] $Headers
)
{
  $pageNumber = 1
  $hasMoreData = $true
  Write-Host "Files Changed:"
  while ($hasMoreData) {
    $url = "https://api.github.com/repos/$($prBaseRepository)/pulls/$pullRequestId/files?per_page=100&page=$pageNumber"
    $response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url

    $changedFiles = $response | ConvertFrom-Json
    ValidateFiles -Files $changedFiles

    if ($response.Headers.ContainsKey("Link") -and ($response.Headers["Link"] -match 'rel=\"next\"')) {
      $pageNumber += 1
    } else {
      $hasMoreData = $false
    }
  }
  Write-Host "Verification completed successfully."
}

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0
$headers = @{             
  "Authorization" = "token $token"
  "Accept"        = "application/vnd.github.baptiste-preview+json"
}


ValidatePullRequest -PullRequestRepository $prBaseRepository -PullRequestId $pullRequestId -Headers $headers
ValidatePullRequestFiles -PullRequestRepository $prBaseRepository -PullRequestId $pullRequestId -Headers $headers