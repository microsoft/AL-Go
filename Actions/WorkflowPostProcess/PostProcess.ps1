Param(
    [Parameter(HelpMessage = "Name of workflow initiating the workflow", Mandatory = $false)]
    [string] $workflowName = $env:GITHUB_WORKFLOW,
    [Parameter(HelpMessage = "Telemetry scope generated during the workflow initialization", Mandatory = $false)]
    $telemetryScopeJson = $null
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper 
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)
    
    $telemetryScope = $telemetryScopeJson| ConvertFrom-Json | ConvertTo-HashTable 

    $localTelemetryScope = CreateScope -eventId $workflowName
}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    TrackTrace -telemetryScope $telemetryScope

    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
