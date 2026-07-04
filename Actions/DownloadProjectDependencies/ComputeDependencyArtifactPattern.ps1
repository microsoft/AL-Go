$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot "../AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot "DownloadProjectDependencies.psm1" -Resolve) -Force -DisableNameChecking

$projectDependencies = $ENV:_projectDependenciesJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
$pattern = Get-DependencyArtifactPattern -Project $ENV:_project -ProjectDependencies $projectDependencies

if ($pattern) {
    Write-Host "Dependency artifact pattern: $pattern"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "hasPattern=true"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "pattern=$pattern"
}
else {
    Write-Host "No dependency projects found, skipping artifact download"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "hasPattern=false"
}
