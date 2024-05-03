[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'GitHub Secrets are transferred as plain text')]
param(
    [Parameter(HelpMessage = "Azure Credentials secret", Mandatory = $true)]
    [string] $AzureCredentialsJson,
    [Parameter(HelpMessage = "The path to the files to be signed", Mandatory = $true)]
    [String] $PathToFiles,
    [Parameter(HelpMessage = "The URI of the timestamp server", Mandatory = $false)]
    [string] $TimestampService = "http://timestamp.digicert.com",
    [Parameter(HelpMessage = "The digest algorithm to use for signing and timestamping", Mandatory = $false)]
    [string] $digestAlgorithm = "sha256"
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Sign.psm1" -Resolve)

$Files = Get-ChildItem -Path $PathToFiles -File | Select-Object -ExpandProperty FullName
if (-not $Files) {
    Write-Host "No files to sign. Exiting."
    return
}

Write-Host "::group::Files to be signed"
$Files | ForEach-Object {
    Write-Host "- $_"
}
Write-Host "::endgroup::"

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

Write-Host "::group::Signing files"
Invoke-SigningTool -KeyVaultName $AzureKeyVaultName `
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