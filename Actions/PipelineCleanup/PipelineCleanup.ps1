Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch
# IMPORTANT: All actions need a try/catch here and not only in the yaml file, else they can silently fail

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0077' -parentTelemetryScopeJson $parentTelemetryScopeJson
    
    if ($project  -eq ".") { $project = "" }

    $containerName = GetContainerName($project)
    Remove-Bccontainer $containerName

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    Write-Host "::ERROR::PipelineCleanup action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    $host.SetShouldExit(1)
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
