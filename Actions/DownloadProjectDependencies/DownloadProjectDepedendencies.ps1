Param(
    [Parameter(HelpMessage = "The project for which to download dependencies", Mandatory = $true)]
    [string] $project,
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "TODO", Mandatory = $false)]
    [string[]] $dependecyProjects = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$downloadedArtifacts= @()

if(!$dependecyProjects -or $dependecyProjects.Count -eq 0) {
    Write-Host "No dependencies to download for project '$project'"
}
else {

}

$downloadedArtifactsJson = ConvertTo-Json $downloadedArtifacts -Depth 99 -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "downloadedArtifacts=$downloadedArtifactsJson"