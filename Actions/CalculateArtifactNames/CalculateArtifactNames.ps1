Param(
    [Parameter(HelpMessage = "", Mandatory = $true)]
    [string] $settings,
    [Parameter(HelpMessage = "", Mandatory = $true)]
    [string] $project,
    [Parameter(HelpMessage = "", Mandatory = $true)]
    [string] $buildMode,
    [Parameter(HelpMessage = "", Mandatory = $true)]
    [string] $refName
)


$settings = '${{ env.Settings }}' | ConvertFrom-Json
$project = '${{ matrix.project }}'
$buildMode = '${{ matrix.buildMode }}'
$refName = ''


$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

if ($project -eq ".") { 
  $project = $settings.repoName 
}

if ($buildMode -eq 'Default') { 
  $buildMode = '' 
}

'Apps','Dependencies','TestApps','TestResults','BcptTestResults','BuildOutput','ContainerEventLog' | ForEach-Object {
  $name = "$($_)ArtifactsName"
  $value = "$($project.Replace('\','_').Replace('/','_'))-$($ref)-$buildMode$_-$($settings.repoVersion).$($settings.appBuild).$($settings.appRevision)"
  Add-Content -Path $env:GITHUB_OUTPUT -Value "$name=$value"
  Add-Content -Path $env:GITHUB_ENV -Value "$name=$value"
}
Add-Content -Path $env:GITHUB_OUTPUT -Value "BuildMode=$buildMode"
Add-Content -Path $env:GITHUB_ENV -Value "BuildMode=$buildMode"
