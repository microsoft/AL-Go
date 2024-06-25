Param(
    [Parameter(HelpMessage = "The event id of the initiating workflow", Mandatory = $true)]
    [string] $eventId,
    [Parameter(HelpMessage = "The repository of the action", Mandatory = $false)]
    [string] $actionsRepo,
    [Parameter(HelpMessage = "The ref of the action", Mandatory = $false)]
    [string] $actionsRef
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

    if ($actionsRepo -eq 'microsoft/AL-Go-Actions') {
        Write-Host "Using AL-Go for GitHub $actionsRef"
        $verstr = $actionsRef
    }
    elseif ($actionsRepo -eq 'microsoft/AL-Go') {
        Write-Host "Using AL-Go for GitHub Preview ($actionsRef)"
        $verstr = "p"
    }
    else {
        Write-Host "Using direct AL-Go development ($($actionsRepo)@$actionsRef)"
        $verstr = "d"
    }

    Write-Big -str "a$verstr"

    TestALGoRepository

    DownloadAndImportBcContainerHelper

    TestRunnerPrerequisites

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

    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "telemetryScopeJson=$scopeJson"
    Write-Host "telemetryScopeJson=$scopeJson"

    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "correlationId=$correlationId"
    Write-Host "correlationId=$correlationId"
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
