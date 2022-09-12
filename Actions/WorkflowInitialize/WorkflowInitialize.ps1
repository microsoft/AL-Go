Param(
    [Parameter(HelpMessage = "The event id of the initiating workflow", Mandatory = $true)]
    [string] $eventId 
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$BcContainerHelperPath = ""

# IMPORTANT: No code that can fail should be outside the try/catch
try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

    $ap = "$ENV:GITHUB_ACTION_PATH".Split('\')
    $branch = $ap[$ap.Count-2]
    $owner = $ap[$ap.Count-4]

    if ($owner -ne "microsoft") {
        $verstr = "d"
    }
    elseif ($branch -eq "preview") {
        $verstr = "p"
    }
    else {
        $verstr = $branch
    }

    Write-Big -str "a$verstr"

    Test-ALGoRepository -baseFolder $ENV:GITHUB_WORKSPACE

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId $eventId
    if ($telemetryScope) {
        AddTelemetryProperty -telemetryScope $telemetryScope -key "repository" -value (GetHash -str $ENV:GITHUB_REPOSITORY)
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runAttempt" -value $ENV:GITHUB_RUN_ATTEMPT
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runNumber" -value $ENV:GITHUB_RUN_NUMBER
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runId" -value $ENV:GITHUB_RUN_ID
        
        $scopeJson = $telemetryScope | ConvertTo-Json -Compress
        $correlationId = ($telemetryScope.CorrelationId).ToString()
    }
    else {
        $scopeJson = "{}"
        $correlationId = [guid]::Empty.ToString()
    }

    Write-Host "  __  __              _                            "
    Write-Host " |  \/  |            | |                           "
    Write-Host " | \  / |_   _    ___| |__   __ _ _ __   __ _  ___ "
    Write-Host " | |\/| | | | |  / __| '_ \ / _` | '_ \ / _` |/ _ \"
    Write-Host " | |  | | |_| | | (__| | | | (_| | | | | (_| |  __/"
    Write-Host " |_|  |_|\__, |  \___|_| |_|\__,_|_| |_|\__, |\___|"
    Write-Host "          __/ |                          __/ |     "
    Write-Host "         |___/                          |___/      "

    Write-Host "::set-output name=telemetryScopeJson::$scopeJson"
    Write-Host "set-output name=telemetryScopeJson::$scopeJson"

    Write-Host "::set-output name=correlationId::$correlationId"
    Write-Host "set-output name=correlationId::$correlationId"

}
catch {
    OutputError -message "WorkflowInitialize action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
