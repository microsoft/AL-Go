Param(
    [string] $actor,
    [string] $token,
    [string] $actionsRepo,
    [string] $perTenantExtensionRepo,
    [string] $appSourceAppRepo
    
)

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

SetTokenAndRepository -actor $actor -token $token -repository ''

RemoveRepository -repository $actionsRepo
RemoveRepository -repository $perTenantExtensionRepo
RemoveRepository -repository $AppSourceAppRepo
