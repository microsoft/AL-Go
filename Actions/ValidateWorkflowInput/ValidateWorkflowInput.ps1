. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "ValidateWorkflowInput.psm1" -Resolve) -Force -DisableNameChecking

$workflowName = "$ENV:GITHUB_WORKFLOW".Trim().Replace(' ','').ToLowerInvariant().Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
$ValidateWorkflowScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-$workflowName.ps1"

# If a workflow references this action, there must be a validate script for it
if (-not (Test-Path -Path $ValidateWorkflowScript)) {
  throw "No validate workflow script found for $workflowName."
}

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$eventPath = Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json

# If a workflow references this action, it must have inputs
if ($null -eq $eventPath.inputs) {
  throw "No inputs found in $env:GITHUB_EVENT_PATH"
}

# Validate the inputs for the workflow - there doesn't have to be validators for all inputs
. $ValidateWorkflowScript -settings $settings -eventPath $eventPath
