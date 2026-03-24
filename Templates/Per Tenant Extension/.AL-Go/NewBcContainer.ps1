Param([Hashtable] $parameters)

$script = Join-Path $PSScriptRoot "../../../Actions/TRASER-Overrides/NewBcContainer.ps1" -Resolve
. $script -parameters $parameters
