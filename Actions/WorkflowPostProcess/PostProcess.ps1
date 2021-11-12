Param(
    [Parameter(HelpMessage = "Name of workflow initiating the workflow", Mandatory = $false)]
    [string] $eventId,
    [Parameter(HelpMessage = "Telemetry scope generated during the workflow initialization", Mandatory = $false)]
    $telemetryScopeJson = $null
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper 
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)


    SetTelemeteryConfiguration
    
    $localTelemetryScope = InitTelemetryScope -name "" -eventId $eventId  -parameterValues @()  -includeParameters @()

    Write-Host "registering parent telemetery scope $telemetryScopeJson"
    $telemetryScope = RegisterTelemetryScope $telemetryScopeJson

    
    $telemetryScope["Emitted"] = $false
    write-Host "scope $($telemetryScope| ConvertTo-Json)"

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
