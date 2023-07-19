Param(
  [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
  [string] $token,
  [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $false)]
  [string] $baseSHA,
  [Parameter(HelpMessage = "Base ref of the PR", Mandatory = $false)]
  [string] $baseRef,
  [Parameter(HelpMessage = "Head commit of the PR", Mandatory = $false)]
  [string] $headSHA,
  [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
  [string] $prBaseRepository
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

function ValidateFiles
(
  [Object[]] $Files
)
{
  $Files | ForEach-Object {
    $filename = $_
    Write-Host "- $filename"
    $extension = [System.IO.Path]::GetExtension($filename)
    $name = [System.IO.Path]::GetFileName($filename)
    if ($extension -eq '.ps1' -or $extension -eq '.yaml' -or $extension -eq '.yml' -or $name -eq "CODEOWNERS" -or $filename.StartsWith(".github/")) {
      throw "Pull Request containing changes to scripts, workflows or CODEOWNERS are not allowed from forks."
    }
  } 
}

git fetch
$filesChanged = git diff $baseSHA..origin/$baseRef --name-only

ValidateFiles -Files $filesChanged