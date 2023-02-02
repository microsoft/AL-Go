Param(
    [Parameter(HelpMessage = "Base commit of the PR", Mandatory = $true)]
    [string] $baseSHA,
    [Parameter(HelpMessage = "HEAD commit of the PR", Mandatory = $true)]
    [string] $headSHA,
    [Parameter(HelpMessage = "The name of the repository the PR is coming from", Mandatory = $true)]
    [string] $prHeadRepository,
    [Parameter(HelpMessage = "The name of the repository the PR is going to", Mandatory = $true)]
    [string] $prBaseRepository,
    [Parameter(HelpMessage = "The URL of the GitHub API", Mandatory = $true)]
    [string] $githubApiUrl

)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0
if ($prHeadRepository -ne $prBaseRepository) {
    $headers = @{             
        "Authorization" = 'token ${{ secrets.GITHUB_TOKEN }}'
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
