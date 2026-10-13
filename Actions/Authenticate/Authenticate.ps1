<#
.SYNOPSIS
Checks Business Central credentials and initiates device login when credentials are unavailable.
.PARAMETER secrets
JSON output from ReadSecrets containing the authentication secrets to check.
.PARAMETER secretNames
Comma-separated secret keys to check in order. The first non-empty value wins.
.PARAMETER authType
Explicit authentication target: AdminCenter or Environment.
.PARAMETER environmentName
Environment to authenticate to. Required for Environment authentication; must be empty for AdminCenter.
#>
Param(
    [Parameter(Mandatory = $true, HelpMessage = "Authentication secrets JSON from ReadSecrets")]
    [string] $secrets,
    [Parameter(Mandatory = $true, HelpMessage = "Comma-separated secret keys in priority order; first non-empty value wins")]
    [string] $secretNames,
    [Parameter(Mandatory = $true, HelpMessage = "Authentication target (AdminCenter or Environment)")]
    [ValidateSet('AdminCenter', 'Environment')]
    [string] $authType,
    [Parameter(HelpMessage = "Environment name; required for Environment and empty for AdminCenter")]
    [string] $environmentName = ''
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot "../AL-Go-Helper.ps1" -Resolve)

$candidateNames = @($secretNames.Split(',') | ForEach-Object { $_.Trim() })
if ($candidateNames -contains '') {
    throw 'secretNames must contain a comma-separated list of non-empty secret keys.'
}
if ($authType -eq 'Environment' -and [string]::IsNullOrWhiteSpace($environmentName)) {
    throw 'environmentName is required for Environment authentication.'
}
if ($authType -eq 'AdminCenter' -and $environmentName) {
    throw 'environmentName must be empty for AdminCenter authentication.'
}

if (-not $secrets.TrimStart().StartsWith('{')) {
    throw 'Authentication secrets must be a JSON object from ReadSecrets.'
}
try {
    $secretValues = $secrets | ConvertFrom-Json | ConvertTo-HashTable -recurse
}
catch {
    # JSON parser errors can include secret values.
    throw 'Authentication secrets must be a valid JSON object from ReadSecrets.'
}

$displayNames = @{}
foreach ($name in $candidateNames) {
    $displayNames[$name] = $name
}
if ($authType -eq 'AdminCenter' -and $candidateNames -contains 'adminCenterApiCredentials') {
    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $displayNames['adminCenterApiCredentials'] = $settings.adminCenterApiCredentialsSecretName
}
$missingSecrets = ($candidateNames | ForEach-Object { $displayNames[$_] }) -join ' or '

if ($authType -eq 'Environment') {
    $description = 'AuthContext'
    $message = "AL-Go needs access to the Business Central Environment $($environmentName.Split(' ')[0]) and could not locate a secret called $missingSecrets"
}
else {
    $description = 'Admin Center Api Credentials'
    $message = "AL-Go needs access to the Business Central Admin Center Api and could not locate a secret called $missingSecrets (https://aka.ms/ALGoSettings#AdminCenterApiCredentialsSecretName)"
}

$selectedSecret = $candidateNames | Where-Object { $secretValues.ContainsKey($_) -and $secretValues[$_] } | Select-Object -First 1
if ($selectedSecret) {
    $displayName = $displayNames[$selectedSecret]
    Write-Host "$description provided in secret $displayName!"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_STEP_SUMMARY -Value "$description was provided in a secret called $displayName. Using this information for authentication."
    return
}

Write-Host "No $description provided, initiating Device Code flow"
DownloadAndImportBcContainerHelper
$authContext = New-BcAuthContext -includeDeviceLogin -deviceLoginTimeout ([TimeSpan]::FromSeconds(0))
$deviceLogin = ConvertTo-HashTable -object $authContext -recurse
if ([string]::IsNullOrWhiteSpace($deviceLogin['deviceCode']) -or [string]::IsNullOrWhiteSpace($deviceLogin['message'])) {
    throw 'Device login did not return a device code and sign-in instructions.'
}

Add-Content -Encoding UTF8 -Path $env:GITHUB_STEP_SUMMARY -Value "$message`n`n$($deviceLogin.message)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "deviceCode=$($deviceLogin.deviceCode)"
