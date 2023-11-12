Write-Host "Event name: $env:GITHUB_EVENT_NAME"
if ($env:GITHUB_EVENT_NAME -eq 'workflow_dispatch') {
  Write-Host "Inputs:"
  $eventPath = Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
  if ($null -ne $eventPath.inputs) {
    $eventPath.inputs.psObject.Properties | Sort-Object { $_.Name } | ForEach-Object {
      $property = $_.Name
      $value = $eventPath.inputs."$property"
      Write-Host "- $property = '$value'"
    }
  }
}
