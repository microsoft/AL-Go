param(
    [Parameter(HelpMessage = "Azure Key Vault URI.", Mandatory = $true)]
    [string] $AzureCredentialsJson,
    [Parameter(HelpMessage = "Paths to the files to be signed.", Mandatory = $true)]
    [String] $PathToFiles,
    [Parameter(HelpMessage = "Timestamp service.", Mandatory = $false)]
    [string] $TimestampService = "http://timestamp.digicert.com",
    [Parameter(HelpMessage = "Timestamp digest algorithm.", Mandatory = $false)]
    [string] $TimestampDigest = "sha256",
    [Parameter(HelpMessage = "File digest algorithm.", Mandatory = $false)]
    [string] $FileDigest = "sha256",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $ParentTelemetryScopeJson = '7b7d'
)

$telemetryScope = $null
$bcContainerHelperPath = $null

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
    $settings = $env:Settings | ConvertFrom-Json
    if ($AzureCredentials.PSobject.Properties.name -eq "keyVaultName") {
        $AzureKeyVaultName = $AzureCredentials.keyVaultName
    } elseif ($settings.PSobject.Properties.name -eq "keyVaultName") {
        $AzureKeyVaultName = $settings.keyVaultName
    } else {
        throw "KeyVaultName is not specified in AzureCredentials nor in settings. Please specify it in one of them."
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
            --azure-key-vault-certificate $Settings.keyVaultCodesignCertificateName `
            --timestamp-rfc3161 "$TimestampService" `
            --timestamp-digest $TimestampDigest `
            $Files
    } -MaxRetries 3
    
    TrackTrace -telemetryScope $telemetryScope
}
catch {
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    throw
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
