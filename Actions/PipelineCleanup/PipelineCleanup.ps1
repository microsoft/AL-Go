Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

Import-Module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    if ($project  -eq ".") { $project = "" }

    $containerName = GetContainerName($project)
    Remove-Bccontainer $containerName

    Trace-Information
}
catch {
    Trace-Exception -ErrorRecord $_
    throw
}
