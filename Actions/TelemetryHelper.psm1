$signals = @{
    "DO0070" = "AL-Go action ran: AddExistingApp"
    "DO0071" = "AL-Go action ran: CheckForUpdates"
    "DO0072" = "AL-Go action ran: CreateApp"
    "DO0073" = "AL-Go action ran: CreateDevelopmentEnvironment"
    "DO0074" = "AL-Go action ran: CreateReleaseNotes"
    "DO0075" = "AL-Go action ran: Deploy"
    "DO0076" = "AL-Go action ran: IncrementVersionNumber"
    "DO0077" = "AL-Go action ran: PipelineCleanup"
    "DO0078" = "AL-Go action ran: ReadSecrets"
    "DO0079" = "AL-Go action ran: ReadSettings"
    "DO0080" = "AL-Go action ran: RunPipeline"

    "DO0090" = "AL-Go workflow ran: AddExistingAppOrTestApp"
    "DO0091" = "AL-Go workflow ran: CiCd"
    "DO0092" = "AL-Go workflow ran: CreateApp"
    "DO0093" = "AL-Go workflow ran: CreateOnlineDevelopmentEnvironment"
    "DO0094" = "AL-Go workflow ran: CreateRelease"
    "DO0095" = "AL-Go workflow ran: CreateTestApp"
    "DO0096" = "AL-Go workflow ran: IncrementVersionNumber"
    "DO0097" = "AL-Go workflow ran: PublishToEnvironment"
    "DO0098" = "AL-Go workflow ran: UpdateGitHubGoSystemFiles"
    "DO0099" = "AL-Go workflow ran: NextMajor"
    "DO0100" = "AL-Go workflow ran: NextMinor"
    "DO0101" = "AL-Go workflow ran: Current"
    "DO0102" = "AL-Go workflow ran: CreatePerformanceTestApp"
}

function CreateScope {
    param (
        [string] $eventId,
        [string] $parentTelemetryScopeJson = '{}'
    )

    $signalName = $signals[$eventId] 
    if (-not $signalName) {
        throw "Invalid event id ($eventId) is enountered."
    }

    if ($parentTelemetryScopeJson -and $parentTelemetryScopeJson -ne "{}") {
        $telemetryScope = RegisterTelemetryScope $parentTelemetryScopeJson
    }

    $telemetryScope = InitTelemetryScope -name $signalName -eventId $eventId  -parameterValues @()  -includeParameters @()

    return $telemetryScope
}

function GetHash {
    param(
        [string] $str
    )

    $stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($str))
    (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}
