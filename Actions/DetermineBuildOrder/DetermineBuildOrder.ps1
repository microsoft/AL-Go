Param(
    [Parameter(HelpMessage = "JSON formatted string of projects to build", Mandatory = $true)]
    [string] $Projects,
    [Parameter(HelpMessage = "JSON formatted build order", Mandatory = $true)]
    [string] $BuildOrder,
    [Parameter(HelpMessage = "Build order depth", Mandatory = $true)]
    [string] $BuildOrderDepth,
    [Parameter(HelpMessage = "Workflow depth", Mandatory = $true)]
    [string] $WorkflowDepth
)

$ErrorActionPreference = "STOP"
Set-StrictMode -version 2.0

Write-Host "Projects=$Projects"
$Projects = $Projects | ConvertFrom-Json
Write-Host "BuildOrder=$BuildOrder"
$BuildOrder = $Projects | ConvertFrom-Json

if ($BuildOrderDepth -lt $WorkflowDepth) {
  Write-Host "::Error::Project Dependencies depth is $BuildOrderDepth. Workflow is only setup for $WorkflowDepth. You need to Run Update AL-Go System Files to update the workflows"
  $host.SetShouldExit(1)
}

$step = $BuildOrderDepth
$BuildOrderDepth..1 | ForEach-Object {
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
