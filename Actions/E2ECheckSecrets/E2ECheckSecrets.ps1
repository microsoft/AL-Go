Param(
    [Parameter(HelpMessage = "GitHub owner (defaults to current repository owner)", Mandatory = $false)]
    [string] $githubOwner = '',
    [Parameter(HelpMessage = "E2E_APP_ID variable value", Mandatory = $false)]
    [string] $e2eAppId = '',
    [Parameter(HelpMessage = "E2E_PRIVATE_KEY secret value", Mandatory = $false)]
    [string] $e2ePrivateKey = '',
    [Parameter(HelpMessage = "ALGOAUTHAPP secret value", Mandatory = $false)]
    [string] $algoAuthApp = '',
    [Parameter(HelpMessage = "adminCenterApiCredentials secret value", Mandatory = $false)]
    [string] $adminCenterApiCredentials = '',
    [Parameter(HelpMessage = "E2E_GHPackagesPAT secret value", Mandatory = $false)]
    [string] $e2eGHPackagesPAT = '',
    [Parameter(HelpMessage = "E2EAZURECREDENTIALS secret value", Mandatory = $false)]
    [string] $e2eAzureCredentials = ''
)

$err = $false
if (($e2eAppId -eq '') -or ($e2ePrivateKey -eq '')){
    Write-Host "::Error::In order to run end to end tests, you need a Secret called E2E_PRIVATE_KEY and a variable called E2E_APP_ID."
    $err = $true
}
if ($algoAuthApp -eq '') {
    Write-Host "::Error::In order to run end to end tests, you need a Secret called ALGOAUTHAPP"
    $err = $true
}
if ($adminCenterApiCredentials -eq '') {
    Write-Host "::Error::In order to run end to end tests, you need a Secret called adminCenterApiCredentials"
    $err = $true
}
if ($e2eGHPackagesPAT -eq '') {
    Write-Host "::Error::In order to run end to end tests, you need a secret called E2E_GHPackagesPAT"
    $err = $true
}
if ($e2eAzureCredentials -eq '') {
    Write-Host "::Error::In order to run end to end tests, you need a secret called E2EAZURECREDENTIALS"
    $err = $true
}
if ($err) {
    exit 1
}
$maxParallel = 99
if (!($githubOwner)) {
    $githubOwner = "$ENV:GITHUB_REPOSITORY_OWNER"
}
$orgmap = Get-Content -path (Join-Path "." "e2eTests\orgmap.json") -encoding UTF8 -raw | ConvertFrom-Json
if ($orgmap.PSObject.Properties.Name -eq $githubOwner) {
    $githubOwner = $orgmap."$githubOwner"
}
if ($githubOwner -eq $ENV:GITHUB_REPOSITORY_OWNER) {
    $maxParallel = 8
}
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "maxParallel=$maxParallel"
Write-Host "maxParallel=$maxParallel"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "githubOwner=$githubOwner"
Write-Host "githubOwner=$githubOwner"
