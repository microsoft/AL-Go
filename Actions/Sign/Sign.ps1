[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'GitHub Secrets are transferred as plain text')]
param(
    [Parameter(HelpMessage = "Azure Credentials secret", Mandatory = $true)]
    [string] $AzureCredentialsJson,
    [Parameter(HelpMessage = "The path to the files to be signed", Mandatory = $true)]
    [String] $PathToFiles,
    [Parameter(HelpMessage = "The URI of the timestamp server", Mandatory = $false)]
    [string] $TimestampService = "http://timestamp.digicert.com",
    [Parameter(HelpMessage = "The digest algorithm to use for signing and timestamping", Mandatory = $false)]
    [string] $digestAlgorithm = "sha256",
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $ParentTelemetryScopeJson = '7b7d'
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Sign.psm1" -Resolve)
    DownloadAndImportBcContainerHelper
    $telemetryScope = CreateScope -eventId 'DO0083' -parentTelemetryScopeJson $ParentTelemetryScopeJson

    Write-Host "::group::Files to be signed"
    $Files = Get-ChildItem -Path $PathToFiles -File | Select-Object -ExpandProperty FullName
    Write-Host "Signing files:"
    $Files | ForEach-Object {
        Write-Host "- $_"
    }
    Write-Host "::endgroup::"

    if (-not $Files) {
        Write-Host "No files to sign. Exiting."
        return
    }

    # Get parameters for signing
    $AzureCredentials = ConvertFrom-Json $AzureCredentialsJson
    $settings = $env:Settings | ConvertFrom-Json
    if ($settings.keyVaultName) {
        $AzureKeyVaultName = $settings.keyVaultName
    }
    elseif ($AzureCredentials.PSobject.Properties.name -eq "keyVaultName") {
        $AzureKeyVaultName = $AzureCredentials.keyVaultName
    }
    else {
        throw "KeyVaultName is not specified in AzureCredentials nor in settings. Please specify it in one of them."
    }
    $description = "Signed with AL-Go for GitHub"
    $descriptionUrl = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"

    # Sign files
    Write-Host "::group::Signing files"
    SignFilesInPath -KeyVaultName $AzureKeyVaultName `
        -CertificateName $settings.keyVaultCodesignCertificateName `
        -ClientId $AzureCredentials.clientId `
        -ClientSecret $AzureCredentials.clientSecret `
        -TenantId $AzureCredentials.tenantId `
        -FilesToSign $PathToFiles `
        -Description $description `
        -DescriptionUrl $descriptionUrl `
        -TimestampService $TimestampService `
        -DigestAlgorithm $digestAlgorithm `
        -Verbosity "Information"
    Write-Host "::endgroup::"
    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
