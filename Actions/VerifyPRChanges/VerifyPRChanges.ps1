Param(
    [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $false)]
    [string] $baseSHA,
    [Parameter(HelpMessage = "Head commit of the PR", Mandatory = $false)]
    [string] $headSHA,
    [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $false)]
    [string] $prBaseRepository,
    [Parameter(HelpMessage = "The name of the repository the PR is coming from", Mandatory = $false)]
    [string] $prHeadRepository,
    [Parameter(HelpMessage = "The URL of the GitHub API", Mandatory = $false)]
    [string] $githubApiUrl,
    [Parameter(HelpMessage = "The token to use for the GitHub API", Mandatory = $false)]
    [string] $githubToken

)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0
if ($prHeadRepository -ne $prBaseRepository) {
    $headers = @{             
        "Authorization" = "token $githubToken"
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }
    $url = "$($githubApiUrl)/repos/$($prBaseRepository)/compare/$baseSHA...$headSHA"
    $response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url | ConvertFrom-Json
    Write-Host "Files Changed:"
    $response.files | ForEach-Object {
      $filename = $_.filename
      Write-Host "- $filename $_.status"
      $extension = [System.IO.Path]::GetExtension($filename)
      $name = [System.IO.Path]::GetFileName($filename)
      if ($extension -eq '.ps1' -or $extension -eq '.yaml' -or $extension -eq '.yml' -or $name -eq "CODEOWNERS") {
        throw "Pull Request containing changes to scripts, workflows or CODEOWNERS are not allowed from forks."
      }
    }
    Write-Host "Verification completed successfully."
} else {
    Write-Host "Pull Request is from the same repository, skipping check."
}
