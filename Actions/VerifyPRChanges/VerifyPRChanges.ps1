Param(
  [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
  [string] $token,
  [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $false)]
  [string] $baseSHA,
  [Parameter(HelpMessage = "Head commit of the PR", Mandatory = $false)]
  [string] $headSHA,
  [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
  [string] $prBaseRepository,
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

#TODO: Revert
$prBaseRepository = "microsoft/AlAppExtensions"
$pullRequestId = "24106"

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0
$headers = @{             
  "Authorization" = "token $token"
  "Accept"        = "application/vnd.github.baptiste-preview+json"
}
$pageNumber = 1
$hasMoreData = $true

Write-Host "Files Changed:"
while ($hasMoreData) {
  $url = "https://api.github.com/repos/$($prBaseRepository)/pulls/$pullRequestId/files?per_page=100&page=$pageNumber"
  $response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url

  $changedFiles = $response | ConvertFrom-Json
  ValidateFiles -Files $changedFiles

  #if ($response.Headers.ContainsKey("Link") -and ($response.Headers["Link"] -match 'rel=\"next\"')) {
  if ($changedFiles.Count -eq 100) { 
    $pageNumber += 1
  } else {
    $hasMoreData = $false
  }
}
Write-Host "Verification completed successfully."
