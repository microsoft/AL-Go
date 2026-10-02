Param(
    [Parameter(HelpMessage = "The GitHub event name that triggered the workflow (override for reusable workflows)", Mandatory = $false)]
    [string] $workflowEventName = "$ENV:GITHUB_EVENT_NAME",
    [Parameter(HelpMessage = "The workflow inputs in compressed JSON format (override for reusable workflows). If not specified, the inputs are read from the GitHub event payload", Mandatory = $false)]
    [string] $inputsJson = ''
)

Write-Host "Event name: $workflowEventName"
if ($workflowEventName -in 'workflow_dispatch', 'workflow_call') {
  Write-Host "Inputs:"
  if ($inputsJson) {
    # Inputs are provided explicitly (e.g. when the workflow is called as a reusable workflow, where the event payload belongs to the caller)
    $inputs = $inputsJson | ConvertFrom-Json
  }
  else {
    $inputs = (Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json).inputs
  }
  if ($null -ne $inputs) {
    $inputs.psObject.Properties | Sort-Object { $_.Name } | ForEach-Object {
      $property = $_.Name
      $value = $inputs."$property"
      Write-Host "- $property = '$value'"
    }
  }
}
