Param(
    [Parameter(HelpMessage = "The event id of the initiating workflow", Mandatory = $true)]
    [string] $eventId
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

    # $ENV:GITHUB_ACTION_PATH is
    #                                      -4       -3         -2       -1
    # linux:            /home/runner/work/owner/AL-Go-Actions/branch/WorkflowInitialize
    # windows:  C:\Users\runneradmin\work\owner\AL-Go-Actions\branch\WorkflowInitialize
    #
    # For Preview (or Direct AL-Go development branch)
    #                                      -5    -4     -3     -2       -1
    # linux:            /home/runner/work/owner/AL-Go/branch/Actions/WorkflowInitialize
    # windows:  C:\Users\runneradmin\work\owner\AL-Go\branch\Actions\WorkflowInitialize
    # or:       C:\Users\runneradmin\work\owner\AL-Go\branch\Actions/WorkflowInitialize
    $ap = "$ENV:GITHUB_ACTION_PATH".Split('/\')
    $branch = $ap[$ap.Count-2]
    $owner = $ap[$ap.Count-4]
    # When using direct AL-Go development, the $ap[$ap.count-2] is the Actions subfolder in the AL-Go repository (see above)
    # meaning that the actual owner and branch are in the $ap[$ap.count-5] and $ap[$ap.count-3] respectively
    # We cannot index from the beginning of the array as the path can be different depending on the agent installation
    if ($branch -eq 'Actions' -and $owner -eq 'AL-Go') {
        # Using Direct AL-Go development branch
        $branch = $ap[$ap.Count-3]
        $owner = $ap[$ap.Count-5]
        if ($owner -eq "microsoft") {
            Write-Host "Using AL-Go for GitHub Preview ($branch)"
            $verstr = "p"
        }
        else {
            Write-Host "Using direct AL-Go development to $owner/AL-Go@$branch"
            $verstr = "d"
        }
    }
    else {
        Write-Host "Using AL-Go for GitHub $branch"
        if ($owner -ne "microsoft") {
            $verstr = "d"
        }
        else {
            $verstr = $branch
        }
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
