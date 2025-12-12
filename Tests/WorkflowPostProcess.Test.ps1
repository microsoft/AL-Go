Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "WorkflowPostProcess Action Tests" {
    BeforeAll {
        $actionName = "WorkflowPostProcess"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    # Call action

    It 'Test DateTime serialization is locale-agnostic' {
        # Dot-source the WorkflowPostProcess script to load the ConvertToUtcDateTime function
        . $scriptPath
        
        # Save the current culture to restore later
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        
        try {
            # Test with different locales to ensure the fix works regardless of culture
            # This simulates the scenario where WorkflowInitialize runs on one machine with one locale
            # and WorkflowPostProcess runs on another machine with a different locale
            $testCultures = @('en-US', 'en-AU', 'de-DE', 'ja-JP')
            
            foreach ($cultureName in $testCultures) {
                # Set the culture to simulate different locale machines
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new($cultureName)
                
                # Simulate what WorkflowInitialize does - serialize a datetime in ISO 8601 format
                $utcNow = [DateTime]::UtcNow
                $scopeJson = @{
                    "workflowStartTime" = $utcNow.ToString("o")
                } | ConvertTo-Json -Compress

                # Simulate what WorkflowPostProcess does - deserialize the datetime
                $telemetryScope = $scopeJson | ConvertFrom-Json

                # Use the ConvertToUtcDateTime function (same logic as in WorkflowPostProcess.ps1)
                $startTimeUtc = ConvertToUtcDateTime -DateTimeValue $telemetryScope.workflowStartTime

                # Verify the parsed datetime is in UTC
                $startTimeUtc.Kind | Should -Be 'Utc' -Because "DateTime should be in UTC regardless of culture ($cultureName)"

                # Verify the parsed datetime is close to the original (within 1 second to account for execution time)
                $timeDiff = [Math]::Abs(($startTimeUtc - $utcNow).TotalSeconds)
                $timeDiff | Should -BeLessThan 1 -Because "Parsed datetime should match original for culture $cultureName"
            }
        }
        finally {
            # Restore the original culture
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }

}
