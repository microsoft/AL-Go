Param(
    [string] $configName = "",
    [string] $githubOwner,
    [string] $token,
    [string] $algoBranch,
    [switch] $github,
    [switch] $directCommit
)

. (Join-Path $PSScriptRoot "Deploy.ps1") -configName $configName -collect -githubOwner $githubOwner -token $token -algoBranch $algoBranch -github:$github -directCOMMIT:$directCOMMIT
