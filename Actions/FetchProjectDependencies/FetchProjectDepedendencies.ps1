Param(
    [Parameter(HelpMessage = "The project for which to fetch dependencies", Mandatory = $true)]
    [string] $project,
    [string] $buildMode = 'Default',
    [string[]] $dependecyProjects = @()
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$fetchedArtifacts= @()

if(!$dependecyProjects -or $dependecyProjects.Count -eq 0) {
    Write-Host "No dependencies to fetch for project '$project'"
}
else {

}


$fetchedArtifactsJson = ConvertTo-Json $fetchedArtifacts -Depth 99 -Compress
Add-Content -Path $env:GITHUB_OUTPUT -Value "FetchedArtifacts=$fetchedArtifactsJson"