Param(
  [string] $workflowName
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "TestWorkflowInput.psm1" -Resolve) -Force

if (-not $workflowName) {
  Write-Host "No workflow name provided. Exiting."
  exit
}

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$errorMessage = ''
$eventPath = Get-Content -Encoding UTF8 -Path $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
if ($null -ne $eventPath.inputs) {
  Write-Host "Inputs:"
  $inputNames = @($eventPath.inputs.psObject.Properties | Sort-Object { $_.Name } | ForEach-Object { $_.Name })
  foreach($inputname in $inputNames) {
    $inputValue = $eventPath.inputs."$inputName"
    $err = ''
    switch ("$($workflowName).$inputName") {
      'CreateRelease.UpdateVersionNumber' {
        $err = Test-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue $inputValue
      }
      'IncrementVersionNumber.VersionNumber' {
        $err = Test-UpdateVersionNumber -settings $settings -inputName $inputName -inputValue $inputValue
      }
      default {
        if ($inputValue -is [boolean]) {
          # Boolean values are always valid
          $err = $null
        }
        else {
          Write-Host "- $inputName = '$inputValue' (no validation)"
          $err = 'OK'
        }
      }
    }
    if ($err -eq 'OK') {
      continue
    }
    elseif ($err) {
      $err = "- $inputName = '$inputValue' ($err)"
      if ($errorMessage -eq '') {
        $errorMessage = 'One or more input values have illegal values'
      }
      $errorMessage += "`n$err"
      Write-Host $err
    }
    else {
      Write-Host "- $inputName = '$inputValue' (OK)"
    }
  }
}
else {
  Write-Host "No inputs found"
}
if ( $errorMessage) {
  throw $errorMessage
}
