Param(
    [Parameter(HelpMessage = "Name of the secret to check (e.g., 'adminCenterApiCredentials' or comma-separated list to check multiple)", Mandatory = $true)]
    [string] $secretName,
    [Parameter(HelpMessage = "Environment name (for error messages)", Mandatory = $false)]
    [string] $environmentName = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json
$secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable

# Check each secret name in order
$authContext = $null
$foundSecretName = ''
foreach ($name in ($secretName -split ',')) {
    $name = $name.Trim()
    if ($secrets.ContainsKey($name) -and $secrets."$name") {
        Write-Host "Using $name secret"
        $authContext = $secrets."$name"
        $foundSecretName = $name
        break
    }
}

if ($authContext) {
    Write-Host "AuthContext provided in secret $foundSecretName!"
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "AuthContext was provided in a secret called $foundSecretName. Using this information for authentication."
}
else {
    Write-Host "No AuthContext provided, initiating Device Code flow"
    DownloadAndImportBcContainerHelper
    $authContext = New-BcAuthContext -includeDeviceLogin -deviceLoginTimeout ([TimeSpan]::FromSeconds(0))

    # Build appropriate error message
    if ($environmentName) {
        $message = "AL-Go needs access to the Business Central Environment $($environmentName.Split(' ')[0]) and could not locate a secret called $($secretName -replace ',', ' or ')"
    }
    else {
        $message = "AL-Go needs access to the Business Central Admin Center Api and could not locate a secret called $($settings.adminCenterApiCredentialsSecretName) (https://aka.ms/ALGoSettings#AdminCenterApiCredentialsSecretName)"
    }

    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_STEP_SUMMARY -Value "$message`n`n$($authContext.message)"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "deviceCode=$($authContext.deviceCode)"
}
