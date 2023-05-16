param(
  [Parameter(Mandatory = $true)]
  [string] $envName,
  [Parameter(Mandatory = $true)]
  [string] $environment,
  [Parameter(Mandatory = $false)]
  [string] $projects
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

$deployToSettingStr = [System.Environment]::GetEnvironmentVariable("DeployTo$envName")
if ($deployToSettingStr) {
  $deployToSettings = $deployToSettingStr | ConvertFrom-Json
}
else {
  $deployToSettings = [PSCustomObject]@{}
}

$authContext = $null
"$($envName)-AuthContext", "$($envName)_AuthContext", "AuthContext" | ForEach-Object {
  if (!($authContext)) {
    $authContext = [System.Environment]::GetEnvironmentVariable($_)
    if ($authContext) {
      Write-Host "Using $_ secret as AuthContext"
    }
  }            
}

if (!($authContext)) {
  Write-Host "::Error::No AuthContext provided"
  exit 1
}

if (("$deployToSettings" -ne "") -and $deployToSettings.PSObject.Properties.name -eq "EnvironmentName") {
  $environmentName = $deployToSettings.environmentName
}
else {
  $environmentName = $null
  "$($envName)-EnvironmentName", "$($envName)_EnvironmentName", "EnvironmentName" | ForEach-Object {
    if (!($EnvironmentName)) {
      $EnvironmentName = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String([System.Environment]::GetEnvironmentVariable($_)))
      if ($EnvironmentName) {
        Write-Host "Using $_ secret as EnvironmentName"
        Write-Host "Please consider using the DeployTo$_ setting instead, where you can specify EnvironmentName, projects and branches"
      }
    }            
  }
  if (!($environmentName)) {
    $environmentName = $envName;
  }
  $deployToSettings | Add-Member -MemberType NoteProperty -name 'environmentName' -value $environmentName
}

$environmentName = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($environmentName + $environment.SubString($envName.Length)).ToUpperInvariant()))
if (("$deployToSettings" -ne "") -and $deployToSettings.PSObject.Properties.name -eq "projects") {
  $projects = $deployToSettings.projects
}
else {
  $projects = [System.Environment]::GetEnvironmentVariable("$($envName)-projects")
  if (-not $projects) {
    $projects = [System.Environment]::GetEnvironmentVariable("$($envName)_Projects")
    if (-not $projects) {
      $projects = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String([System.Environment]::GetEnvironmentVariable('projects')))
    }
  }
  $deployToSettings | Add-Member -MemberType NoteProperty -Name 'projects' -Value $projects
}

$powerPlatformSolutionFolder = [System.Environment]::GetEnvironmentVariable('PowerPlatformSolutionFolder')
$deployPP = $false

if ($projects -eq '' -or $projects -eq '*') {
  $projects = '*'
  $deployPP = ("$powerPlatformSolutionFolder" -ne "")
}
else {
  $buildProjects = $projects | ConvertFrom-Json
  $projects = ($projects.Split(',') | Where-Object { 
      $deployALProject = $buildProjects -contains $_
      if ($_ -eq $powerPlatformSolutionFolder) {
        $deployPP = $true
        $deployALProject = $false
      }
      $deployALProject
    }) -join ','
}

Add-Content -Path $env:GITHUB_ENV -Value "authContext=$authContext"
Write-Host "authContext=$authContext"
Add-Content -Path $env:GITHUB_ENV -Value "deployTo=$($deployToSettings | ConvertTo-Json -depth 99 -compress)"
Write-Host "deployTo=$deployToSettings"
Add-Content -Path $env:GITHUB_ENV -Value "environmentName=$environmentName"
Write-Host "environmentName=$([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($environmentName)))"
Write-Host "environmentName (as Base64)=$environmentName"
Add-Content -Path $env:GITHUB_ENV -Value "projects=$projects"
Write-Host "projects=$projects"
Add-Content -Path $env:GITHUB_ENV -Value "deployPP=$deployPP"
Write-Host "deployPP=$deployPP"
