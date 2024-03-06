<#
    .SYNOPSIS
    Installs the dotnet signing tool.
    .DESCRIPTION
    Installs the dotnet signing tool if isn't already installed.
    If you want to avoid installing it on-demand while signing you can run ´dotnet tool install sign --version $Version --global´ to install it on your machine
    .PARAMETER Version
    The version of the signing tool to install.
#>
function Install-SignTool() {
        param(
            [Parameter(Mandatory = $false)]
            [string] $Version
        )

        if (Get-Command -Name "sign" -ErrorAction SilentlyContinue) {
            Write-Host "Signing tool is already installed"
        } else {
            Write-Host "Signing tool not found. Installing version $Version locally."
            dotnet tool install sign --version $Version --tool-path SigningTool
            Set-Alias -Name sign -Value "SigningTool\sign.exe" -Scope Local
        }
}

<#
    .SYNOPSIS
    Signs files in a given path using a certificate from Azure Key Vault.
    .DESCRIPTION
    Signs files in a given path using a certificate from Azure Key Vault.
    .PARAMETER KeyVaultName
    The name of the Azure Key Vault where the certificate is stored.
    .PARAMETER CertificateName
    The name of the certificate in the Azure Key Vault.
    .PARAMETER ClientId
    The client ID of the service principal used to authenticate with Azure Key Vault.
    .PARAMETER ClientSecret
    The client secret of the service principal used to authenticate with Azure Key Vault.
    .PARAMETER TenantId
    The tenant ID of the service principal used to authenticate with Azure Key Vault.
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
    Invoke-SigningTool -KeyVaultName "my-key-vault" -CertificateName "my-certificatename" -ClientId "my-client-id" -ClientSecret "my-client-secret" -TenantId "my-tenant-id"
                    -FilesToSign "C:\path\to\files\*.app" -Description "Signed with AL-Go for GitHub" -DescriptionUrl "github.com/myorg/myrepo"
#>
function Invoke-SigningTool() {
    param(
        [Parameter(Mandatory = $true)]
        [string] $KeyVaultName,
        [Parameter(Mandatory = $true)]
        [string] $CertificateName,
        [Parameter(Mandatory = $true)]
        [string] $ClientId,
        [Parameter(Mandatory = $true)]
        [string] $ClientSecret,
        [Parameter(Mandatory = $true)]
        [string] $TenantId,
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

    # Sign files
    sign code azure-key-vault `
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

Export-ModuleMember -Function Invoke-SigningTool
Export-ModuleMember -Function Install-SignTool