Param(
    [string] $configName = ""
)

. (Join-Path $PSScriptRoot "Deploy.ps1") -configName $configName -collect
