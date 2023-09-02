Param(
    [switch] $github,
    [string] $githubOwner,
    [string] $token,
    [string] $actionsRepo,
    [string] $perTenantExtensionRepo,
    [string] $appSourceAppRepo

)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository ''

RemoveRepository -repository "$githubOwner/$actionsRepo"
RemoveRepository -repository "$githubOwner/$perTenantExtensionRepo"
RemoveRepository -repository "$githubOwner/$AppSourceAppRepo"

EXIT 0 # This is needed to make sure the script exits with 0, otherwise the pipeline might fail