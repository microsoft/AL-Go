param(
    [String]$PathToFiles,
    [String[]]$FileExtensionsToSign = @(".app"),
    [string]$AzureKeyVaultURI,
    [string]$AzureKeyVaultClientID,
    [string]$AzureKeyVaultClientSecret,
    [string]$AzureKeyVaultTenantID,
    [string]$AzureKeyVaultCertificateName,
    [string]$TimestampService = "http://timestamp.digicert.com",
    [string]$TimestampDigest = "sha256",
    [string]$FileDigest = "sha256"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE 

    Register-NavSip

    $Files = Get-FilesWithExtensions -PathToFiles $PathToFiles -Extensions $FileExtensionsToSign
    Write-Host "Signing files:"
    $Files | ForEach-Object { 
        Write-Host "- $_" 
    }

    AzureSignTool sign --file-digest $FileDigest `
        --azure-key-vault-url $AzureKeyVaultURI `
        --azure-key-vault-client-id $AzureKeyVaultClientID `
        --azure-key-vault-tenant-id $AzureKeyVaultTenantID `
        --azure-key-vault-client-secret $AzureKeyVaultClientSecret `
        --azure-key-vault-certificate $AzureKeyVaultCertificateName `
        --timestamp-rfc3161 "$TimestampService" `
        --timestamp-digest $TimestampDigest `
        --verbose `
        $Files
}
catch {
    OutputError -message "AnalyzeTests action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}