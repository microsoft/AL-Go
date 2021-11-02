Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

$BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

if ($project  -eq ".") { $project = "" }

try {
    $containerName = GetContainerName($project)
    Remove-Bccontainer $containerName
}
finally {
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
