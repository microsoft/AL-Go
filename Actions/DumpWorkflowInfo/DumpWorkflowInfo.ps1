Param(
    [Parameter(HelpMessage = "The GitHub event name that triggered the workflow (override for reusable workflows)", Mandatory = $false)]
    [string] $workflowEventName = "$ENV:GITHUB_EVENT_NAME",
    [Parameter(HelpMessage = "The workflow inputs in compressed JSON format (override for reusable workflows). If not specified, the inputs are read from the GitHub event payload", Mandatory = $false)]
    [string] $inputsJson = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Event name: $workflowEventName"
if ($workflowEventName -in 'workflow_dispatch', 'workflow_call') {
  Write-Host "Inputs:"
  if ($inputsJson) {
    # Inputs are provided explicitly (e.g. when the workflow is called as a reusable workflow, where the event payload belongs to the caller)
    $inputs = $inputsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
  }
  else {
    $inputs = (Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json | ConvertTo-HashTable -recurse).inputs
  }
  if ($null -ne $inputs) {
    $inputs.Keys | Sort-Object | ForEach-Object {
      Write-Host "- $_ = '$($inputs."$_")'"
    }
  }
}
