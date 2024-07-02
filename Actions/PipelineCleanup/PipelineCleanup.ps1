Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

if ($project -eq ".") { $project = "" }

$containerName = GetContainerName($project)
Remove-Bccontainer $containerName
