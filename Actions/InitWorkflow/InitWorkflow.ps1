Param(
    [Parameter(HelpMessage = "Name of workflow initiating the workflow", Mandatory = $false)]
    [string] $workflowName 
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper 
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)
    
    $telemetryScope = CreateScope -eventId $workflowName

    if (-not $telemetryScope.CorrelationId) {
        $telemetryScope["CorrelationId"] = (New-Guid).ToString()
    } 

    $scopeJson = $telemetryScope | ConvertTo-Json -Compress
    Write-Host "::set-output name=telemetryScope::$scopeJson"
    Write-Host "set-output name=telemetryScope::$scopeJson"

    $correlationId = ($telemetryScope.CorrelationId).ToString()
    Write-Host "::set-output name=correlationId::$correlationId"
    Write-Host "set-output name=correlationId::$correlationId"
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
