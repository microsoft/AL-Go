Param(
    [string] $configName = ""
    [string] $githubOwner,
    [string] $token,
    [string] $srcBranch,
    [switch] $github,
    [switch] $directCommit
)

. (Join-Path $PSScriptRoot "Deploy.ps1") -configName $configName -collect -githubOwner $githubOwner -token $token -srcBranch $srcBranch -github:$github -directCOMMIT:$directCOMMIT
