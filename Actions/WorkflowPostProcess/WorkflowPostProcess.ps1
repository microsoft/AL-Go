Param(
    [Parameter(HelpMessage = "The event Id of the initiating workflow", Mandatory = $true)]
    [string] $eventId,
    [Parameter(HelpMessage = "Telemetry scope generated during the workflow initialization", Mandatory = $false)]
    [string] $telemetryScopeJson = '7b7d'
)

$telemetryScope = $null
$bcContainerHelperPath = $null

function Get-WorkflowStatus([string] $RunId) {
    $workflowJobs = gh api /repos/aholstrup1/ALAppExtensions/actions/runs/$RunId/jobs | ConvertFrom-Json
    $failedJobs = $workflowJobs.Jobs | Where-Object { $_.conclusion -eq "failure" }

    if ($failedJobs) {
        throw "Workflow failed with the following jobs: $($failedJobs.name -join ', ')"
    }
}

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)

    if ($telemetryScopeJson -and $telemetryScopeJson -ne '7b7d') {
        $telemetryScope = RegisterTelemetryScope (hexStrToStr -hexStr $telemetryScopeJson)
        TrackTrace -telemetryScope $telemetryScope
    }

    Get-WorkflowStatus -RunId $Env:GITHUB_RUN_ID
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
