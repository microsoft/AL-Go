<#
.SYNOPSIS
Validates and installs the Copilot CLI version supported by the review engine.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$requested = $Version.Trim()
if ($requested -notmatch '\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*))?\z') {
    throw "copilotCliVersion must be an exact semantic version; received '$requested'."
}

$policyPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'copilot-cli-compatibility.psd1'
$policy = Import-PowerShellDataFile -Path $policyPath -ErrorAction Stop
if ($policy.schema_version -ne 1 -or -not $policy.supported_versions.ContainsKey($requested)) {
    throw "Copilot CLI version '$requested' has not been compatibility-validated by the engine policy."
}

& npm install --global "@github/copilot@$requested"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install Copilot CLI version '$requested'."
}
& copilot --version
if ($LASTEXITCODE -ne 0) {
    throw "Copilot CLI version '$requested' did not start successfully."
}
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "version=$requested"
