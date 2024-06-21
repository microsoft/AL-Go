<#
    .SYNOPSIS
    Installs the dotnet signing tool.
    .DESCRIPTION
    Installs the dotnet signing tool.
#>
function Install-SigningTool() {
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

        # Create folder in temp directory with a unique name
        $tempFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) "SigningTool-$(Get-Random)"

        # Get version of the signing tool
        $version = Get-PackageVersion -PackageName "sign"

        # Install the signing tool in the temp folder
        Write-Host "Installing signing tool version $version in $tempFolder"
        New-Item -ItemType Directory -Path $tempFolder | Out-Null
        dotnet tool install sign --version $version --tool-path $tempFolder | Out-Null

        # Return the path to the signing tool
        $signingTool = Join-Path -Path $tempFolder "sign.exe" -Resolve
        return $signingTool
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

    $signingToolExe = Install-SigningTool

    # Sign files
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

Export-ModuleMember -Function Invoke-SigningTool
