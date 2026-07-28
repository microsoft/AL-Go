Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "Path to folder containing previous release apps for upgrade testing", Mandatory = $false)]
    [string] $previousAppsPath = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\.Modules\PipelinePhases.psm1" -Resolve) -DisableNameChecking
DownloadAndImportBcContainerHelper

$context = Initialize-PipelineContext -token $token -project $project -buildMode $buildMode
$saved = Restore-PipelineContext -project $project
# Re-hydrate cross-step state (the container credential) onto the freshly built context.
$context.containerName = $saved.containerName
if ($saved.Keys -contains 'containerPassword') { $context.containerPassword = $saved.containerPassword }

$context = Publish-AlGoApps -context $context -previousAppsPath $previousAppsPath

$persisted = @{
    "containerName"      = $context.containerName
    "environmentCreated" = [bool]($saved.environmentCreated)
}
if ($context.Keys -contains 'containerPassword') { $persisted["containerPassword"] = $context.containerPassword }
if ($saved.Keys -contains 'testToolkitInstalled') { $persisted["testToolkitInstalled"] = [bool]$saved.testToolkitInstalled }
if ($context.Keys -contains 'publishedApps') { $persisted["publishedApps"] = @($context.publishedApps) }
Save-PipelineContext -context $persisted -project $project | Out-Null
