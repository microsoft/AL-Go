Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper

    if ($project -eq ".") { $project = "" }

    $containerName = GetContainerName($project)
    $projectPath = Join-Path $ENV:GITHUB_WORKSPACE $project

    # Capture event log before removing container
    if (Test-BcContainer -containerName $containerName) {
        try {
            Write-Host "Get Event Log from container"
            $containerEventLogFile = Join-Path $projectPath "ContainerEventLog.evtx"
            $eventlogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
            Copy-Item -Path $eventLogFile -Destination $containerEventLogFile
        }
        catch {
            Write-Host "Error getting event log from container: $($_.Exception.Message)"
        }
    }

    Remove-BcContainerSession -containerName $containerName -killPsSessionProcess
    Remove-BcContainer $containerName

    # Clean up volume-backed temp folder for self-hosted runners
    $containerBaseFolder = $env:containerBaseFolder
    if ($containerBaseFolder -and (Test-Path $containerBaseFolder)) {
        Write-Host "Removing temp folder $containerBaseFolder"
        Remove-Item -Path (Join-Path $projectPath '*') -Recurse -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host "Pipeline Cleanup failed: $($_.Exception.Message)"
}
