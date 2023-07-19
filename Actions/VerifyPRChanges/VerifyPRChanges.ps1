Param(
  [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
  [string] $token,
  [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $false)]
  [string] $baseSHA,
  [string] $baseRef,
  [Parameter(HelpMessage = "Head commit of the PR", Mandatory = $false)]
  [string] $headSHA,
  [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
  [string] $prBaseRepository
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0
git fetch
$diff = git diff HEAD..origin/$baseRef --name-only

Write-Host $diff