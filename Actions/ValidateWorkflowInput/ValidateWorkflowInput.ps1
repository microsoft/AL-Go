Param(
    [Parameter(HelpMessage = "The name of the workflow for which the inputs are validated (override for reusable workflows)", Mandatory = $false)]
    [string] $workflowName = "$ENV:GITHUB_WORKFLOW",
    [Parameter(HelpMessage = "The workflow inputs in compressed JSON format (override for reusable workflows). If not specified, the inputs are read from the GitHub event payload", Mandatory = $false)]
    [string] $inputsJson = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "ValidateWorkflowInput.psm1" -Resolve) -Force -DisableNameChecking

$workflowName = $workflowName.Trim().Replace(' ','').ToLowerInvariant().Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
$ValidateWorkflowScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-$workflowName.ps1"

# If a workflow references this action, there must be a validate script for it
if (-not (Test-Path -Path $ValidateWorkflowScript)) {
  throw "No validate workflow script found for $workflowName."
}

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
if ($inputsJson) {
  # Inputs are provided explicitly (e.g. when the workflow is called as a reusable workflow, where the event payload belongs to the caller)
  $eventPath = [PSCustomObject]@{ "inputs" = ($inputsJson | ConvertFrom-Json) }
}
else {
  $eventPath = Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
}

# If a workflow references this action, it must have inputs
if ($null -eq $eventPath.inputs) {
  throw "No inputs found in $(if ($inputsJson) { 'inputsJson' } else { $env:GITHUB_EVENT_PATH })"
}

# Validate the inputs for the workflow - there doesn't have to be validators for all inputs
. $ValidateWorkflowScript -settings $settings -eventPath $eventPath
