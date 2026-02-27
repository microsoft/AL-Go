Param(
    [Parameter(HelpMessage = "GitHub owner for test repositories", Mandatory = $true)]
    [string] $githubOwner,
    [Parameter(HelpMessage = "BcContainerHelper version", Mandatory = $false)]
    [string] $bcContainerHelperVersion = ''
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
. (Join-Path "." "e2eTests/SetupRepositories.ps1") -githubOwner $githubOwner -bcContainerHelperVersion $bcContainerHelperVersion
