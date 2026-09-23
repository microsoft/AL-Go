Param(
    [Parameter(HelpMessage = "GitHub owner for test repositories", Mandatory = $false)]
    [string] $githubOwner = ''
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "repoName=$repoName"
Write-Host "repoName=$repoName"
if ($githubOwner) {
    Write-Host "Repo URL: https://github.com/$githubOwner/$repoName"
}
