param (
    [Parameter(Mandatory=$false, HelpMessage="The GitHub owner from the input.")]
    [string]$githubOwner
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

if (!($githubOwner)) {
    $githubOwner = "$ENV:GITHUB_REPOSITORY_OWNER"
}

$orgmap = Get-Content -Path (Join-Path "..\.." "e2eTests\orgmap.json") -Encoding UTF8 -Raw | ConvertFrom-Json
if ($orgmap.PSObject.Properties.Name -eq $githubOwner) {
  $githubOwner = $orgmap."$githubOwner"
}

Write-Host "githubOwner=$githubOwner"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "githubOwner=$githubOwner"
