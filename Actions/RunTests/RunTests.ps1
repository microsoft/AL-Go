Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\.Modules\PipelinePhases.psm1" -Resolve) -DisableNameChecking
DownloadAndImportBcContainerHelper

$context = Initialize-PipelineContext -token $token -project $project -buildMode $buildMode
$saved = Restore-PipelineContext -project $project
$context.containerName = $saved.containerName
if ($saved.Keys -contains 'containerPassword') { $context.containerPassword = $saved.containerPassword }

Invoke-AlGoTests -context $context | Out-Null
