Param(
    [Parameter(HelpMessage = "Actions Repository", Mandatory = $true)]
    [string] $actionsRepo,
    [Parameter(HelpMessage = "Actions Ref", Mandatory = $true)]
    [string] $actionsRef
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Write-Host "Current action repository: $actionsRepo"
Write-Host "Current action ref: $actionsRef"

# Set the path where the actions will be checked out
# Default path is ./_AL-Go/Actions
$actionsPath = './_AL-Go/Actions'
if ($actionsRepo -like '*/AL-Go') { # direct development
  # Set the path one level up as that where the Actions folder will be
  $actionsPath = './_AL-Go'
}
Add-Content -encoding utf8 -Path $env:GITHUB_ENV -Value "actionsRepo=$actionsRepo"
Add-Content -encoding utf8 -Path $env:GITHUB_ENV -Value "actionsRef=$actionsRef"
Add-Content -encoding utf8 -Path $env:GITHUB_ENV -Value "actionsPath=$actionsPath"
