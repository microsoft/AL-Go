Param(
  [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
  [string] $token,
  [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $false)]
  [string] $baseSHA,
  [Parameter(HelpMessage = "Head commit of the PR", Mandatory = $false)]
  [string] $headSHA,
  [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
  [string] $prBaseRepository
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0
$headers = @{             
  "Authorization" = "token $token"
  "Accept"        = "application/vnd.github.baptiste-preview+json"
}
$url = "https://api.github.com/repos/$($prBaseRepository)/compare/$baseSHA...$headSHA"
$response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url | ConvertFrom-Json
Write-Host "Files Changed:"
$response.files | ForEach-Object {
  $filename = $_.filename
  Write-Host "- $filename $_.status"
  $extension = [System.IO.Path]::GetExtension($filename)
  $name = [System.IO.Path]::GetFileName($filename)
  if ($extension -eq '.ps1' -or $extension -eq '.yaml' -or $extension -eq '.yml' -or $name -eq "CODEOWNERS" -or $filename.StartsWith(".github/")) {
    throw "Pull Request containing changes to scripts, workflows or CODEOWNERS are not allowed from forks."
  }
}
Write-Host "Verification completed successfully."
