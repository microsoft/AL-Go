param(
    [Parameter(Mandatory = $true)]
    [string] $ActionName,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action,
    [Parameter(Mandatory = $false)]
    [switch]$SkipTelemetry
)

$errorActionPreference = "Stop"
$progressPreference = "SilentlyContinue"
Set-StrictMode -Version 2.0

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "TelemetryHelper.psm1" -Resolve)

$AdditionalData = @{}
try {
    $startTime = Get-Date
    Invoke-Command -ScriptBlock $Action

    if (-not $SkipTelemetry) {
        $AdditionalData["ActionDuration"] = ((Get-Date) - $startTime).TotalSeconds
        Trace-Information -ActionName $ActionName -AdditionalData $AdditionalData
    }
}
catch {
    if (-not $SkipTelemetry) {
        $AdditionalData["ActionDuration"] = ((Get-Date) - $startTime).TotalSeconds
        Trace-Exception -ActionName $ActionName -ErrorRecord $_ -AdditionalData $AdditionalData
    }

    Write-Host "::ERROR::Unexpected error when running action. Error Message: $($_.Exception.Message.Replace("`r",'').Replace("`n",' ')), StackTrace: $($_.ScriptStackTrace.Replace("`r",'').Replace("`n",' <- '))";
    exit 1
}
