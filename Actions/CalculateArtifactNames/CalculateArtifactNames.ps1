Param(
    [Parameter(HelpMessage = "settings", Mandatory = $true)]
    [string] $settingsJson,
    [Parameter(HelpMessage = "project", Mandatory = $true)]
    [string] $project,
    [Parameter(HelpMessage = "buildmode", Mandatory = $true)]
    [string] $buildMode,
    [Parameter(HelpMessage = "refname", Mandatory = $true)]
    [string] $refName,
    [switch] $runLocally
)

function Set-EnvVariable([string]$name, [string]$value, [switch]$runLocally) {
    Write-Host "Assigning $value to $name"
    if ($runLocally) {
        [Environment]::SetEnvironmentVariable($name, $value)
    } else {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "$name=$value"
        Add-Content -Path $env:GITHUB_ENV -Value "$name=$value"
    }
}


$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

Write-Host $settingsJson
$settings = $settingsJson | ConvertFrom-Json

if ($project -eq ".") { 
  $project = $settings.repoName 
}

if ($buildMode -eq 'Default') { 
  $buildMode = '' 
}

'Apps','Dependencies','TestApps','TestResults','BcptTestResults','BuildOutput','ContainerEventLog' | ForEach-Object {
  $name = "$($_)ArtifactsName"
  $value = "$($project.Replace('\','_').Replace('/','_'))-$($refName)-$buildMode$_-$($settings.repoVersion).$($settings.appBuild).$($settings.appRevision)"
  Set-EnvVariable -name $name -value $value -runLocally:$runLocally
}
Set-EnvVariable -name "BuildMode" -value $buildMode -runLocally:$runLocally
