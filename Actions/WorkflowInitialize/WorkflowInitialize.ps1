Param(
    [Parameter(HelpMessage = "The event id of the initiating workflow", Mandatory = $true)]
    [string] $eventId
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

    Write-Host "---> $ENV:GITHUB_ACTION_PATH"
    $ap = "$ENV:GITHUB_ACTION_PATH".Split([System.IO.Path]::DirectorySeparatorChar)
    $branch = $ap[$ap.Count-2]
    $owner = $ap[$ap.Count-4]
    if ($branch -eq 'Actions' -and $owner -eq 'AL-Go') {
        # Using Direct AL-Go development branch
        $branch = $ap[$ap.Count-3]
        $owner = $ap[$ap.Count-5]
        Write-Host "Using direct AL-Go development to $owner/AL-Go@$branch"
        $verstr = "d"
    }
    else {
        Write-Host "Using AL-Go for GitHub $branch"
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
    }

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
