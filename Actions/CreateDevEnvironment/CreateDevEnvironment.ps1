Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $false)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\.Modules\PipelinePhases.psm1" -Resolve) -DisableNameChecking
DownloadAndImportBcContainerHelper

$context = Initialize-PipelineContext -token $token -project $project -buildMode $buildMode -artifact $artifact
$context = New-AlGoDevEnvironment -context $context -installAppsJson $installAppsJson -installTestAppsJson $installTestAppsJson

# Persist only the cross-step state that later phases cannot re-derive (never secrets).
$persisted = @{
    "containerName"      = $context.containerName
    "environmentCreated" = [bool]$context.environmentCreated
}
if ($context.Keys -contains 'containerPassword') { $persisted["containerPassword"] = $context.containerPassword }
if ($context.Keys -contains 'testToolkitInstalled') { $persisted["testToolkitInstalled"] = [bool]$context.testToolkitInstalled }
Save-PipelineContext -context $persisted -project $project | Out-Null

Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "containerName=$($context.containerName)"
