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
    "DO0081" = "AL-Go action ran: Deliver"
    "DO0082" = "AL-Go action ran: AnalyzeTests"

    "DO0090" = "AL-Go workflow ran: AddExistingAppOrTestApp"
    "DO0091" = "AL-Go workflow ran: CICD"
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
    "DO0103" = "AL-Go workflow ran: PublishToAppSource"
    "DO0104" = "AL-Go workflow ran: PullRequestHandler"
}

Function strToHexStr {
    Param(
        [string] $str
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($str)
    $hexStr = [System.Text.StringBuilder]::new($Bytes.Length * 2)
    ForEach($byte in $Bytes){
        $hexStr.AppendFormat("{0:x2}", $byte) | Out-Null
    }
    $hexStr.ToString()
}

Function hexStrToStr {
    Param(
        [String] $hexStr
    )
    $Bytes = [byte[]]::new($hexStr.Length / 2)
    For($i=0; $i -lt $hexStr.Length; $i+=2){
        $Bytes[$i/2] = [convert]::ToByte($hexStr.Substring($i, 2), 16)
    }
    [System.Text.Encoding]::UTF8.GetString($Bytes)
}

function CreateScope {
    param (
        [string] $eventId,
        [string] $parentTelemetryScopeJson = '7b7d'
    )

    $signalName = $signals[$eventId] 
    if (-not $signalName) {
        throw "Invalid event id ($eventId) is enountered."
    }

    if ($parentTelemetryScopeJson -and $parentTelemetryScopeJson -ne '7b7d') {
        RegisterTelemetryScope (hexStrToStr -hexStr $parentTelemetryScopeJson) | Out-Null
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
