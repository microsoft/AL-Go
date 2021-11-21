Param(
    [Parameter(HelpMessage = "The event id of the initiating workflow", Mandatory = $true)]
    [string] $eventId 
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper 
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    
    $telemetryScope = CreateScope -eventId $eventId
    if ($telemetryScope) {
        $scopeJson = $telemetryScope | ConvertTo-Json -Compress
        $correlationId = ($telemetryScope.CorrelationId).ToString()
    }
    else {
        $scopeJson = "{}"
        $correlationId = [guid]::Empty.ToString()
    }
    Write-Host "::set-output name=telemetryScopeJson::$scopeJson"
    Write-Host "set-output name=telemetryScopeJson::$scopeJson"

    Write-Host "::set-output name=correlationId::$correlationId"
    Write-Host "set-output name=correlationId::$correlationId"

}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
