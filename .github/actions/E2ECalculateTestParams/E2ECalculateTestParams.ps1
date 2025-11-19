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

# Calculate adminCenterApiCredentials
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

# Add outputs
if ($adminCenterApiCredentials) {
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "adminCenterApiCredentials='$adminCenterApiCredentials'"
}
else {
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "adminCenterApiCredentials=''"
}

if ($template) {
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "template='$template'"
}

if ($contentPath) {
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "contentPath='$contentPath'"
}

# Generate repo name
$reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "repoName='$repoName'"
Write-Host "repoName='$repoName'"
Write-Host "Repo URL: https://github.com/$githubOwner/$repoName"
