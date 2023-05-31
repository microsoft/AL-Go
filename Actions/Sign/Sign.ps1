param(
    [Parameter(HelpMessage = "Azure Key Vault URI.", Mandatory = $true)]
    [string]$AzureCredentialsJson,
    [Parameter(HelpMessage = "Azure Key Vault URI.", Mandatory = $true)]
    [string]$SettingsJson,
    [Parameter(HelpMessage = "Paths to the files to be signed.", Mandatory = $true)]
    [String]$PathToFiles,
    [Parameter(HelpMessage = "Timestamp service.", Mandatory = $false)]
    [string]$TimestampService = "http://timestamp.digicert.com",
    [Parameter(HelpMessage = "Timestamp digest algorithm.", Mandatory = $false)]
    [string]$TimestampDigest = "sha256",
    [Parameter(HelpMessage = "File digest algorithm.", Mandatory = $false)]
    [string]$FileDigest = "sha256",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $ParentTelemetryScopeJson = '7b7d'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Sign.psm1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE
    $telemetryScope = CreateScope -eventId 'DO0083' -parentTelemetryScopeJson $ParentTelemetryScopeJson

    Write-Host "::group::Install AzureSignTool"
    dotnet tool install --global AzureSignTool --version 4.0.1
    Write-Host "::endgroup::"

    $Files = Get-ChildItem -Path $PathToFiles -File | Select-Object -ExpandProperty FullName
    Write-Host "Signing files:"
    $Files | ForEach-Object { 
        Write-Host "- $_" 
    }

    $AzureCredentials = ConvertFrom-Json $AzureCredentialsJson
    $Settings = ConvertFrom-Json $SettingsJson

    if ($Settings.AzureKeyVaultName -eq $null) {
        $AzureKeyVaultName = $AzureCredentials.AzureKeyVaultName
    } else {
        $AzureKeyVaultName = $Settings.AzureKeyVaultName
    }

    Retry-Command -Command {
        Write-Host "::group::Register NavSip"
        Register-NavSip 
        Write-Host "::endgroup::"

        AzureSignTool sign --file-digest $FileDigest `
            --azure-key-vault-url "https://$AzureKeyVaultName.vault.azure.net/" `
            --azure-key-vault-client-id $AzureCredentials.clientId `
            --azure-key-vault-tenant-id $AzureCredentials.tenantId `
            --azure-key-vault-client-secret $AzureCredentials.clientSecret `
            --azure-key-vault-certificate $Settings.AzureyVaultCertificateName `
            --timestamp-rfc3161 "$TimestampService" `
            --timestamp-digest $TimestampDigest `
            $Files
    } -MaxRetries 3
    
    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "Sign action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
