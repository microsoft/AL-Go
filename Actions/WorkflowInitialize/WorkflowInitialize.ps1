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
        $repoSettings = Get-Content -Path (Join-Path $ENV:GITHUB_WORKSPACE '.github/AL-Go-Settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
        $type = 'PTE'
        if ($repoSettings.Keys -contains 'type') {
            $type = $repoSettings.type
        }
        $templateUrl = 'Not set'
        if ($repoSettings.Keys -contains 'templateUrl') {
            $templateUrl = $repoSettings.templateUrl
        }
        if ($verstr -eq "d") {
            $verstr = "Developer/Private"
        }
        elseif ($verstr -eq "p") {
            $verstr = "Preview"
        }
        AddTelemetryProperty -telemetryScope $telemetryScope -key "ALGoVersion" -value $verstr
        AddTelemetryProperty -telemetryScope $telemetryScope -key "type" -value $type
        AddTelemetryProperty -telemetryScope $telemetryScope -key "templateUrl" -value $templateUrl
        AddTelemetryProperty -telemetryScope $telemetryScope -key "repository" -value $ENV:GITHUB_REPOSITORY
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runAttempt" -value $ENV:GITHUB_RUN_ATTEMPT
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runNumber" -value $ENV:GITHUB_RUN_NUMBER
        AddTelemetryProperty -telemetryScope $telemetryScope -key "runId" -value $ENV:GITHUB_RUN_ID
        
        $scopeJson = strToHexStr -str ($telemetryScope | ConvertTo-Json -Compress)
        $correlationId = ($telemetryScope.CorrelationId).ToString()
    }
    else {
        $scopeJson = '7b7d'
        $correlationId = [guid]::Empty.ToString()
    }

    Add-Content -Path $env:GITHUB_OUTPUT -Value "telemetryScopeJson=$scopeJson"
    Write-Host "telemetryScopeJson=$scopeJson"

    Add-Content -Path $env:GITHUB_OUTPUT -Value "correlationId=$correlationId"
    Write-Host "correlationId=$correlationId"
}
catch {
    OutputError -message "WorkflowInitialize action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
