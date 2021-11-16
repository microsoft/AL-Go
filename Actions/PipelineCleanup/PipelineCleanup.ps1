Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the Telemetry signal", Mandatory = $true)]
    [string] $parentTelemetryScope
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")
$BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE
import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)

$telemetryScope = CreateScope -eventId 'DO0077' -parentTelemetryScope $parentTelemetryScope

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
