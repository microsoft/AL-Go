Param(
    [Parameter(HelpMessage = "JSON formatted string of projects to build", Mandatory = $true)]
    [string] $projectsJson,
    [Parameter(HelpMessage = "JSON formatted build order", Mandatory = $true)]
    [string] $buildOrderJson,
    [Parameter(HelpMessage = "Build order depth", Mandatory = $true)]
    [int] $buildOrderDepth,
    [Parameter(HelpMessage = "Workflow depth", Mandatory = $true)]
    [int] $workflowDepth
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

Write-Host "Projects=$projectsJson"
$Projects = $projectsJson | ConvertFrom-Json
Write-Host "BuildOrder=$buildOrderJson"
$BuildOrder = $buildOrderJson | ConvertFrom-Json

if ($buildOrderDepth -lt $workflowDepth) {
  Write-Host "::Error::Project Dependencies depth is $buildOrderDepth. Workflow is only setup for $workflowDepth. You need to Run Update AL-Go System Files to update the workflows"
  $host.SetShouldExit(1)
}

$step = $buildOrderDepth
$buildOrderDepth..1 | ForEach-Object {
  $ps = @($BuildOrder."$_" | Where-Object { $Projects -contains $_ })
  if ($ps.Count -eq 1) {
    $projectsJSon = "[$($ps | ConvertTo-Json -compress)]"
  }
  else {
    $projectsJSon = $ps | ConvertTo-Json -compress
  }
  if ($ps.Count -gt 0) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "projects$($step)Json=$projectsJson"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "projects$($step)Count=$($ps.count)"
    Write-Host "projects$($step)Json=$projectsJson"
    Write-Host "projects$($step)Count=$($ps.count)"
    $step--
  }
}
while ($step -ge 1) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "projects$($step)Json="
    Add-Content -Path $env:GITHUB_OUTPUT -Value "projects$($step)Count=0"
    Write-Host "projects$($step)Json="
    Write-Host "projects$($step)Count=0"
    $step--
}
