. (Get-Item "C:\src\github\microsoft\navcontainerhelper\Import-BcContainerHelper.ps1").FullName

$ErrorActionPreference = "STOP"; Set-StrictMode -Version 2.0
$ENV:GITHUB_API_URL = "https://api.github.com"

$useMyALGoRepo = $true

if ($useMyALGoRepo) {
    $repo = (invoke-git remote get-url origin -returnValue -silent) -replace '.*github.com[:/]|\.git$',''
    $branch = git branch --show-current
    $global:pteTemplate = "$repo@$branch|Templates/Per Tenant Extension"
    $global:appSourceTemplate = "$repo@$branch|Templates/AppSource App"
} else {
    $global:pteTemplate = "microsoft/AL-Go-PTE@preview"
    $global:appSourceTemplate = "microsoft/AL-Go-AppSource@preview"
}

if (-not (Get-Variable -Name 'KeyVaultName' -Scope Global -ErrorAction SilentlyContinue)) {
    $global:KeyVaultName = Read-Host -Prompt "Enter the name of the Key Vault to use for getting secrets for E2E tests"
}
if (-not (Get-Variable -Name 'E2EgitHubOwner' -Scope Global -ErrorAction SilentlyContinue)) {
    $global:E2EgitHubOwner = Read-Host -Prompt "Enter the name of the GitHub organization in which all end 2 end tests should run"
}

Write-Host "Using:"
Write-Host "- KeyVault $($Global:KeyVaultName)"
Write-Host "- E2EgitHubOwner $($Global:E2EgitHubOwner)"
Write-Host "- PTE Template: $($global:pteTemplate)"
Write-Host "- AppSource Template: $($global:appSourceTemplate)"

# Authenticate to GitHub
gh auth status
gh auth refresh --scopes repo,admin:org,workflow,write:packages,read:packages,delete:packages,user,delete_repo
$ENV:GH_TOKEN = invoke-gh auth token -silent -returnValue

Write-Host "Reading secrets from KeyVault:"
# Get Variables needed for end 2 end tests from Key Vault
'ALGoAuthApp','AdminCenterApiCredentials','AzureCredentials' | ForEach-Object {
    Write-Host "- $_"
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $_
    Set-Variable -Name "Secure$_" -Value $secret.SecretValue -Scope Global
}
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'SecureGitHubPackagesToken', Justification = 'E2E Prep script.')]
$global:SecureGitHubPackagesToken = ConvertTo-SecureString -string (invoke-gh auth token -silent -returnValue) -AsPlainText -Force
