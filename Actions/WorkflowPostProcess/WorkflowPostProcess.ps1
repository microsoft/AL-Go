Param(
    [Parameter(HelpMessage = "The event Id of the initiating workflow", Mandatory = $true)]
    [string] $eventId,
    [Parameter(HelpMessage = "Telemetry scope generated during the workflow initialization", Mandatory = $false)]
    [string] $telemetryScopeJson = '7b7d'
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)

    Write-Host "Post-processing workflow $eventId"
    if ($telemetryScopeJson -and $telemetryScopeJson -ne '7b7d') {
        $telemetryScope = RegisterTelemetryScope (hexStrToStr -hexStr $telemetryScopeJson)
        TrackTrace -telemetryScope $telemetryScope
    }
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
