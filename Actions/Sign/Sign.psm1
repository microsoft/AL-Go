<#
    .SYNOPSIS
    Installs the dotnet signing tool.
    .DESCRIPTION
    Installs the dotnet signing tool.
#>
function Install-SigningTool() {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

    $signToolFolder = Install-DotNetTool -PackageName sign

    # Return the path to the signing tool
    $signingTool = Join-Path -Path $signToolFolder "sign.exe"
    return $signingTool
}

<#
    .SYNOPSIS
    Signs files in a given path using a certificate from Azure Key Vault.
    .DESCRIPTION
    Signs files in a given path using a certificate from Azure Key Vault.
    Connection to the Azure Key Vault can be done using a service principal or a managed identity.
    .PARAMETER KeyVaultName
    The name of the Azure Key Vault where the certificate is stored.
    .PARAMETER CertificateName
    The name of the certificate in the Azure Key Vault.
    .PARAMETER ClientId
    [Optional] The client ID of the service principal used to authenticate with Azure Key Vault. If not specified, managed identity will be used.
    .PARAMETER ClientSecret
    [Optional] The client secret of the service principal used to authenticate with Azure Key Vault. If not specified, managed identity will be used.
    .PARAMETER TenantId
    [Optional] The tenant ID of the service principal used to authenticate with Azure Key Vault. If not specified, managed identity will be used.
    .PARAMETER FilesToSign
    The path to the file(s) to be signed. Supports wildcards.
    .PARAMETER Description
    The description to be included in the signature.
    .PARAMETER DescriptionUrl
    The URL to be included in the signature.
    .PARAMETER TimestampService
    The URL of the timestamp server.
    .PARAMETER DigestAlgorithm
    The digest algorithm to use for signing and timestamping.
    .PARAMETER Verbosity
    The verbosity level of the signing tool.
    .EXAMPLE
    Invoke-SigningTool -KeyVaultName "my-key-vault" -CertificateName "my-certificatename" -ClientId "my-client-id" -ClientSecret "my-client-secret" -TenantId "my-tenant-id" `
                    -FilesToSign "C:\path\to\files\*.app" -Description "Signed with AL-Go for GitHub" -DescriptionUrl "github.com/myorg/myrepo"
    .EXAMPLE
    Invoke-SigningTool -KeyVaultName "my-key-vault" -CertificateName "my-certificatename" -FilesToSign "C:\path\to\files\*.app" -Description "Signed with AL-Go for GitHub" -DescriptionUrl "github.com/myorg/myrepo"
#>
function Invoke-SigningTool() {
    param(
        [Parameter(Mandatory = $true, ParameterSetName="KeyVaultSigning")]
        [string] $KeyVaultName,
        [Parameter(Mandatory = $true, ParameterSetName="KeyVaultSigning")]
        [string] $CertificateName,
        [Parameter(Mandatory = $false, ParameterSetName="KeyVaultSigning")]
        [string] $ClientId,
        [Parameter(Mandatory = $false, ParameterSetName="KeyVaultSigning")]
        [string] $ClientSecret,
        [Parameter(Mandatory = $false, ParameterSetName="KeyVaultSigning")]
        [string] $TenantId,
        [Parameter(Mandatory = $true, ParameterSetName="TrustedSigning")]
        [string] $SigningEndpoint,
        [Parameter(Mandatory = $true, ParameterSetName="TrustedSigning")]
        [string] $SigningAccount,
        [Parameter(Mandatory = $true, ParameterSetName="TrustedSigning")]
        [string] $SigningCertificateProfile,
        [Parameter(Mandatory = $true)]
        [string] $FilesToSign,
        [Parameter(Mandatory = $true)]
        [string] $Description,
        [Parameter(Mandatory = $true)]
        [string] $DescriptionUrl,
        [Parameter(Mandatory = $false)]
        [string] $TimestampService = "http://timestamp.digicert.com",
        [Parameter(Mandatory = $false)]
        [string] $DigestAlgorithm = "sha256",
        [Parameter(Mandatory = $false)]
        [string] $Verbosity = "Information"
    )

    $signingToolExe = Install-SigningTool

    # Sign files
    if ($PsCmdlet.ParameterSetName -eq "TrustedSigning") {
        Write-Host "Invoking signing tool using trusted signing"
        . $signingToolExe code trusted-signing `
            --trusted-signing-endpoint $SigningEndpoint `
            --trusted-signing-account $SigningAccount `
            --trusted-signing-certificate-profile $SigningCertificateProfile `
            --description $Description `
            --description-url $DescriptionUrl `
            --file-digest $DigestAlgorithm `
            --timestamp-digest $DigestAlgorithm `
            --timestamp-url $TimestampService `
            --verbosity $Verbosity `
            $FilesToSign
    }
    else {
        if ($ClientId -and $ClientSecret -and $TenantId) {
            Write-Host "Invoking signing tool using clientId/clientSecret"
            . $signingToolExe code azure-key-vault `
                --azure-key-vault-url "https://$KeyVaultName.vault.azure.net/" `
                --azure-key-vault-certificate $CertificateName `
                --azure-key-vault-client-id $ClientId `
                --azure-key-vault-client-secret $ClientSecret `
                --azure-key-vault-tenant-id $TenantId `
                --description $Description `
                --description-url $DescriptionUrl `
                --file-digest $DigestAlgorithm `
                --timestamp-digest $DigestAlgorithm `
                --timestamp-url $TimestampService `
                --verbosity $Verbosity `
                $FilesToSign
        }
        else {
            Write-Host "Invoking signing tool using managed identity"
            . $signingToolExe code azure-key-vault `
                --azure-key-vault-url "https://$KeyVaultName.vault.azure.net/" `
                --azure-key-vault-certificate $CertificateName `
                --azure-key-vault-managed-identity $true `
                --description $Description `
                --description-url $DescriptionUrl `
                --file-digest $DigestAlgorithm `
                --timestamp-digest $DigestAlgorithm `
                --timestamp-url $TimestampService `
                --verbosity $Verbosity `
                $FilesToSign
        }
    }
}

Export-ModuleMember -Function Invoke-SigningTool
