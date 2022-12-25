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

SetTokenAndRepository  -githubOwner $githubOwner -token $token -repository '' -github:$github

RemoveRepository -repository "$githubOwner/$actionsRepo"
RemoveRepository -repository "$githubOwner/$perTenantExtensionRepo"
RemoveRepository -repository "$githubOwner/$AppSourceAppRepo"

EXIT 0 # This is needed to make sure the script exits with 0, otherwise the pipeline might fail