Param(
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$artifactsRetentionDays = 0

Write-Host $ENV:GITHUB_ACTION_PATH

# Set output variables
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ArtifactsRetentionDays=$artifactsRetentionDays"

Write-Host "ArtifactsRetentionDays=$artifactsRetentionDays"
