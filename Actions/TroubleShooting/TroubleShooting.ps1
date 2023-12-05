Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [string] $gitHubSecrets = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "TroubleShoot.Secrets.ps1" -Resolve) -ArgumentList $gitHubSecrets
