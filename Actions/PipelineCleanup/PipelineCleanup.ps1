Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the Telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScope, 
    [Parameter(HelpMessage = "Specifies the event Id in the telemetry", Mandatory = $false)]
    [string] $telemetryEventId,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
$BcContainerHelperPath = DownloadAndImportBcContainerHelper 
import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)

$telemetryScope = CreateScope -eventId $telemetryEventId -parentTelemetryScope $parentTelemetryScope

if ($project  -eq ".") { $project = "" }

try {
    $containerName = GetContainerName($project)
    Remove-Bccontainer $containerName

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
