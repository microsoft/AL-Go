Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Keep the development environment (container) after the build/test", Mandatory = $false)]
    [bool] $keepEnvironment = $false
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\.Modules\PipelinePhases.psm1" -Resolve) -DisableNameChecking
DownloadAndImportBcContainerHelper

$saved = $null
try {
    $saved = Restore-PipelineContext -project $project
}
catch {
    Write-Host "No pipeline context found - nothing to remove. $($_.Exception.Message)"
}

if ($saved -and $saved.containerName) {
    $projectFolder = $project
    if ($projectFolder -eq '.') { $projectFolder = '' }
    $context = @{
        "containerName" = $saved.containerName
        "projectPath"   = (Join-Path $ENV:GITHUB_WORKSPACE $projectFolder)
    }
    # Forward whether a development environment was actually created so Remove-AlGoDevEnvironment
    # can skip the Docker probe entirely when nothing was created (e.g. doNotPublishApps).
    if ($saved.ContainsKey('environmentCreated')) {
        $context.environmentCreated = $saved.environmentCreated
    }
    Remove-AlGoDevEnvironment -context $context -keepEnvironment:$keepEnvironment
}
