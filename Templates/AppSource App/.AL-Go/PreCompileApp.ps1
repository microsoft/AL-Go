Param([Hashtable] $parameters)

$script = Join-Path $PSScriptRoot "../../../Actions/TRASER-Overrides/PreCompileApp.ps1" -Resolve
. $script -parameters $parameters
