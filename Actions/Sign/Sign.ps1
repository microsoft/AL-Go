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

function InstallKeyVaultModuleIfNeeded {
    if (Get-Module -Name 'Az.KeyVault') {
        # Already installed
        return
    }
    if ($isWindows) {
        # GitHub hosted Windows Runners have AZ PowerShell module saved in C:\Modules\az_*
        # Remove AzureRm modules from PSModulePath and add AZ modules
        if (Test-Path 'C:\Modules\az_*') {
            $azModulesPath = Get-ChildItem 'C:\Modules\az_*' | Where-Object { $_.PSIsContainer }
            if ($azModulesPath) {
              Write-Host "Adding AZ module path: $($azModulesPath.FullName)"
              $ENV:PSModulePath = "$($azModulesPath.FullName);$(("$ENV:PSModulePath".Split(';') | Where-Object { $_ -notlike 'C:\\Modules\Azure*' }) -join ';')"
            }
        }
    }
    else {
        # Linux runners have AZ PowerShell module saved in /usr/share/powershell/Modules/Az.*
    }
    $azKeyVaultModule = Get-Module -name 'Az.KeyVault' -ListAvailable | Select-Object -First 1
    if ($azKeyVaultModule) {
        Write-Host "Az.KeyVault Module is available in version $($azKeyVaultModule.Version)"
        Write-Host "Using Az.KeyVault version $($azKeyVaultModule.Version)"
    }
    else {
        $AzKeyVaultModule = Get-InstalledModule -Name 'Az.KeyVault' -ErrorAction SilentlyContinue
        if ($AzKeyVaultModule) {
            Write-Host "Az.KeyVault version $($AzKeyVaultModule.Version) is installed"
        }
        else {
            Write-Host "Installing and importing Az.KeyVault"
            Install-Module 'Az.KeyVault' -Force
        }
    }
    Import-Module  'Az.KeyVault' -DisableNameChecking -WarningAction SilentlyContinue | Out-Null
}

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "Sign.psm1" -Resolve)
    DownloadAndImportBcContainerHelper
    $telemetryScope = CreateScope -eventId 'DO0083' -parentTelemetryScopeJson $ParentTelemetryScopeJson

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
    $AzureCredentialParams = @{
        "ClientId" = $AzureCredentials.clientId
        "TenantId" = $AzureCredentials.tenantId
    }
    if ($AzureCredentials.PSobject.Properties.name -eq "clientSecret") {
        $AzureCredentialParams += @{ "ClientSecret" = $AzureCredentials.clientSecret }
    }
    else {
        Write-Host "Query ID_TOKEN from $ENV:ACTIONS_ID_TOKEN_REQUEST_URL"
        $result = Invoke-RestMethod -Method GET -UseBasicParsing -Headers @{ "Authorization" = "bearer $ENV:ACTIONS_ID_TOKEN_REQUEST_TOKEN"; "Accept" = "application/vnd.github+json" } -Uri "$ENV:ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
        InstallKeyVaultModuleIfNeeded
        Connect-AzAccount -ApplicationId $AzureCredentials.ClientId -Tenant $AzureCredentials.TenantId -FederatedToken $result.value -WarningAction SilentlyContinue | Out-Null
        if ($AzureCredentials.PSObject.Properties.Name -eq 'SubScriptionId') {
            Set-AzContext -SubscriptionId $AzureCredentials.SubscriptionId -Tenant $AzureCredentials.TenantId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
        }
    }
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
    Invoke-SigningTool @$AzureCredentialParams -KeyVaultName $AzureKeyVaultName `
        -CertificateName $settings.keyVaultCodesignCertificateName `
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
