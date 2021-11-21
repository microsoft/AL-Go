Param(
    [switch] $github,
    [string] $githubOwner,
    [string] $token,
    [string] $actionsRepo,
    [string] $perTenantExtensionRepo,
    [string] $appSourceAppRepo
    
)

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

SetTokenAndRepository  -github:$github -githubOwner $githubOwner -token $token -repository ''

RemoveRepository -repository "https://github.com/$githubOwner/$actionsRepo"
RemoveRepository -repository "https://github.com/$githubOwner/$perTenantExtensionRepo"
RemoveRepository -repository "https://github.com/$githubOwner/$AppSourceAppRepo"
