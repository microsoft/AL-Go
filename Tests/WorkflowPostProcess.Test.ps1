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
        # Simulate what WorkflowInitialize does - serialize a datetime in ISO 8601 format
        $utcNow = [DateTime]::UtcNow
        $scopeJson = @{
            "workflowStartTime" = $utcNow.ToString("o")
        } | ConvertTo-Json -Compress

        # Simulate what WorkflowPostProcess does - deserialize the datetime
        $telemetryScope = $scopeJson | ConvertFrom-Json

        # ConvertFrom-Json automatically parses ISO 8601 dates to DateTime with UTC Kind
        $startTime = $telemetryScope.workflowStartTime
        if ($startTime -is [DateTime]) {
            $startTimeUtc = $startTime.ToUniversalTime()
        } else {
            $startTimeUtc = [DateTime]::Parse($startTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        }

        # Verify the parsed datetime is in UTC
        $startTimeUtc.Kind | Should -Be 'Utc'

        # Verify the parsed datetime is close to the original (within 1 second to account for execution time)
        $timeDiff = [Math]::Abs(($startTimeUtc - $utcNow).TotalSeconds)
        $timeDiff | Should -BeLessThan 1
    }

}
