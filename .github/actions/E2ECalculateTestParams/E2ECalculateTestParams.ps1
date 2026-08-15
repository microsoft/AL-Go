[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'GitHub Secrets are transferred as plain text')]
Param(
    [Parameter(HelpMessage = "GitHub owner for test repositories", Mandatory = $true)]
    [string] $githubOwner,
    [Parameter(HelpMessage = "Matrix type (PTE or appSourceApp)", Mandatory = $false)]
    [string] $matrixType = '',
    [Parameter(HelpMessage = "Matrix style (singleProject or multiProject)", Mandatory = $false)]
    [string] $matrixStyle = '',
    [Parameter(HelpMessage = "Matrix OS (windows or linux)", Mandatory = $false)]
    [string] $matrixOs = '',
    [Parameter(HelpMessage = "Admin center API credentials secret", Mandatory = $false)]
    [string] $adminCenterApiCredentialsSecret = '',
    [Parameter(HelpMessage = "AppSource app repository template", Mandatory = $true)]
    [string] $appSourceAppRepo,
    [Parameter(HelpMessage = "Per-tenant extension repository template", Mandatory = $true)]
    [string] $perTenantExtensionRepo,
    [Parameter(HelpMessage = "Content path (for upgrade tests)", Mandatory = $false)]
    [string] $contentPath = ''
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

<#
.SYNOPSIS
Calculates the template, contentPath and adminCenterApiCredentials for an E2E test run based on the matrix cell.
.DESCRIPTION
Given the matrix coordinates (type/style/os) and the repository templates, this function returns the parameters
used to run a single E2E test. It is pure (no side effects) so it can be unit tested in isolation:
- adminCenterApiCredentials is only forwarded for the PTE / singleProject / windows cell.
- template is derived from the matrix type and the corresponding repository template.
- contentPath defaults to 'appsourceapp' or 'pte' when not explicitly provided (used by upgrade tests).
.PARAMETER githubOwner
The GitHub owner that hosts the temporary test repositories.
.PARAMETER matrixType
The matrix type, either 'appSourceApp' or 'PTE'.
.PARAMETER matrixStyle
The matrix style, either 'singleProject' or 'multiProject'.
.PARAMETER matrixOs
The matrix operating system, either 'windows' or 'linux'.
.PARAMETER adminCenterApiCredentialsSecret
The admin center API credentials secret, only forwarded for the PTE / singleProject / windows cell.
.PARAMETER appSourceAppRepo
The AppSource app repository template name.
.PARAMETER perTenantExtensionRepo
The per-tenant extension (PTE) repository template name.
.PARAMETER contentPath
Optional explicit content path (for upgrade tests). Defaulted based on matrixType when empty.
.EXAMPLE
Get-E2ECalculatedTestParams -githubOwner 'contoso' -matrixType 'PTE' -matrixStyle 'singleProject' -matrixOs 'windows' -appSourceAppRepo 'appsource' -perTenantExtensionRepo 'pte'
#>
function Get-E2ECalculatedTestParams {
    Param(
        [Parameter(Mandatory = $false)]
        [string] $githubOwner = '',
        [Parameter(Mandatory = $false)]
        [string] $matrixType = '',
        [Parameter(Mandatory = $false)]
        [string] $matrixStyle = '',
        [Parameter(Mandatory = $false)]
        [string] $matrixOs = '',
        [Parameter(Mandatory = $false)]
        [string] $adminCenterApiCredentialsSecret = '',
        [Parameter(Mandatory = $false)]
        [string] $appSourceAppRepo = '',
        [Parameter(Mandatory = $false)]
        [string] $perTenantExtensionRepo = '',
        [Parameter(Mandatory = $false)]
        [string] $contentPath = ''
    )

    # Calculate adminCenterApiCredentials (only used for the PTE / singleProject / windows cell)
    $adminCenterApiCredentials = ''
    if ($matrixType -eq 'PTE' -and $matrixStyle -eq 'singleProject' -and $matrixOs -eq 'windows') {
        $adminCenterApiCredentials = $adminCenterApiCredentialsSecret
    }

    # Calculate template
    $template = ''
    if ($matrixType -eq 'appSourceApp') {
        $template = "$githubOwner/$appSourceAppRepo"
    }
    elseif ($matrixType -eq 'PTE') {
        $template = "$githubOwner/$perTenantExtensionRepo"
    }

    # Calculate contentPath if not provided
    if (-not $contentPath -and $matrixType) {
        if ($matrixType -eq 'appSourceApp') {
            $contentPath = 'appsourceapp'
        }
        else {
            $contentPath = 'pte'
        }
    }

    return @{
        adminCenterApiCredentials = $adminCenterApiCredentials
        template = $template
        contentPath = $contentPath
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $testParams = Get-E2ECalculatedTestParams `
        -githubOwner $githubOwner `
        -matrixType $matrixType `
        -matrixStyle $matrixStyle `
        -matrixOs $matrixOs `
        -adminCenterApiCredentialsSecret $adminCenterApiCredentialsSecret `
        -appSourceAppRepo $appSourceAppRepo `
        -perTenantExtensionRepo $perTenantExtensionRepo `
        -contentPath $contentPath

    # Add outputs
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "adminCenterApiCredentials=$($testParams.adminCenterApiCredentials)"

    if ($testParams.template) {
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "template=$($testParams.template)"
    }

    if ($testParams.contentPath) {
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "contentPath=$($testParams.contentPath)"
    }

    # Generate repo name
    $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "repoName=$repoName"
    Write-Host "repoName=$repoName"
    Write-Host "Repo URL: https://github.com/$githubOwner/$repoName"
}
