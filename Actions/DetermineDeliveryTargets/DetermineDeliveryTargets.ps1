Param(
    [Parameter(HelpMessage = "projectsJson", Mandatory = $true)]
    [string] $projectsJson,
    [Parameter(HelpMessage = "settings", Mandatory = $true)]
    [string] $settingsJson,
    [Parameter(HelpMessage = "workspace", Mandatory = $true)]
    [string] $workspace,
    [Parameter(HelpMessage = "type", Mandatory = $true)]
    [string] $type,
    [Parameter(HelpMessage = "refName", Mandatory = $true)]
    [string] $refName,
    [switch] $runLocally
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

function Set-GithubOutput([string]$name, [string]$value, [switch]$runLocally) {
    Write-Host "Assigning $value to $name"
    if ($runLocally) {
        [Environment]::SetEnvironmentVariable($name, $value)
    } else {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "$name=$value"
    }
}

function Set-EnvVariable([string]$name, [string]$value, [switch]$runLocally) {
    Write-Host "Assigning $value to $name"
    if ($runLocally) {
        [Environment]::SetEnvironmentVariable($name, $value)
    } else {
        Add-Content -Path $env:GITHUB_ENV -Value "$name=$value"
    }
}

function Get-DeliveryTargets($projects, $settings, $type) {
  $deliveryTargets = @('GitHubPackages','NuGet','Storage')

  if ($type -eq "AppSource App") {
    $continuousDelivery = $false
    
    # For multi-project repositories, we will add deliveryTarget AppSource if any project has AppSourceContinuousDelivery set to true
    $projects | where-Object { $_ } | ForEach-Object {
      $settings = Get-Content (Join-Path $_ '.AL-Go/settings.json') -raw | ConvertFrom-Json
      if (($projectSettings.PSObject.Properties.Name -eq 'AppSourceContinuousDelivery') -and $settings.AppSourceContinuousDelivery) {
        Write-Host "Project $_ is setup for Continuous Delivery"
        $continuousDelivery = $true
      }
    }
    if ($continuousDelivery) {
      $deliveryTargets += @("AppSource")
    }
  }
  
  $namePrefix = 'DeliverTo'
  Get-Item -Path (Join-Path $workspace ".github/$($namePrefix)*.ps1") | ForEach-Object {
    $deliveryTarget = [System.IO.Path]::GetFileNameWithoutExtension($_.Name.SubString($namePrefix.Length))
    $deliveryTargets += @($deliveryTarget)
  }

  return $deliveryTargets
}

$projects = $projectsJson | ConvertFrom-Json
$settings = $settingsJson | ConvertFrom-Json

$deliveryTargets = Get-DeliveryTargets -projects $projects -settings $settings -type $type

$deliveryTargets = @($deliveryTargets | Select-Object -unique | Where-Object {
  $include = $false
  $contextName = "$($_)Context"
  Write-Host "Checking Context: $contextName"
  $deliveryContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String([System.Environment]::GetEnvironmentVariable($contextName)))
  if ($deliveryContext) {
    $settingName = "DeliverTo$_"
    if (($settings.PSObject.Properties.Name -eq $settingName) -and ($settings."$settingName".PSObject.Properties.Name -eq "Branches")) {
      Write-Host "Branches:"
      $settings."$settingName".Branches | ForEach-Object {
        Write-Host "- $_"
        if ($refName -like $_) {
          $include = $true
        }
      }
    }
    else {
      $include = ($refName -eq 'main')
    }
  }
  if ($include) {
    Write-Host "DeliveryTarget $_ included"
  }
  $include
})

$deliveryTargetsJson = $deliveryTargets | ConvertTo-Json -Depth 99 -compress
if ($deliveryTargets.Count -lt 2) { 
  $deliveryTargetsJson = "[$($deliveryTargetsJson)]" 
}

Set-GithubOutput -name "DeliveryTargetsJson" -value $deliveryTargetsJson -runLocally:$runLocally
Set-GithubOutput -name "DeliveryTargetCount" -value $deliveryTargets.Count -runLocally:$runLocally
Set-EnvVariable -name "DeliveryTargets" -value $deliveryTargetsJson -runLocally:$runLocally
