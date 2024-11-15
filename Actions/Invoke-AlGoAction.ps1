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

try {
    Invoke-Command -ScriptBlock $Action

    if (-not $SkipTelemetry) {
        Trace-Information -ActionName $ActionName
    }
}
catch {
    if (-not $SkipTelemetry) {
        Trace-Exception -ActionName $ActionName -ErrorRecord $_
    }

    Write-Host "::ERROR::Unexpected error when running action. Error Message: $($_.Exception.Message.Replace("`r",'').Replace("`n",' ')), StackTrace: $($_.ScriptStackTrace.Replace("`r",'').Replace("`n",' <- '))";
    exit 1
}
