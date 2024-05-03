param(
    [scriptblock]$Action
)

$errorActionPreference = "Stop"
$progressPreference = "SilentlyContinue"
Set-StrictMode -Version 2.0

Import-Module (Join-Path -path $PSScriptRoot -ChildPath "TelemetryHelper.psm1" -Resolve)

try {
    Invoke-Command -ScriptBlock $Action

    # Log telemetry
    Trace-Information
}
catch {
    Trace-Exception -ErrorRecord $_
    Write-Host "::ERROR::Unexpected error when running action. Error Message: $($_.Exception.Message.Replace("`r",'').Replace("`n",' ')), StackTrace: $($_.ScriptStackTrace.Replace("`r",'').Replace("`n",' <- '))";
    exit 1
}