<#
.SYNOPSIS
Helper functions for WorkflowPostProcess action

.DESCRIPTION
Contains utility functions used by the WorkflowPostProcess action and its tests
#>

<#
.SYNOPSIS
Calculate the duration of a workflow from a start time

.DESCRIPTION
Calculates the duration in seconds from the provided start time to the current UTC time.
Handles both DateTime objects and string representations in any date format that can be parsed by the invariant culture (e.g., ISO 8601 or other culture-independent formats).

.PARAMETER StartTime
The workflow start time as either a DateTime object or a string in any date format that can be parsed by the invariant culture (such as ISO 8601 or other culture-independent formats)

.PARAMETER EndTime
(Optional) The end time as a DateTime object. Defaults to the current UTC time.

.EXAMPLE
$duration = GetWorkflowDuration -StartTime "2025-12-12T10:00:00.0000000Z" -EndTime ([DateTime]::UtcNow)

.EXAMPLE
$duration = GetWorkflowDuration -StartTime ([DateTime]::UtcNow)
#>
function GetWorkflowDuration {
    Param(
        [Parameter(Mandatory = $true)]
        $StartTime,
        [Parameter(Mandatory = $false)]
        $EndTime = [DateTime]::UtcNow
    )

    if ($StartTime -is [DateTime]) {
        $workflowStartTime = $StartTime.ToUniversalTime()
    } else {
        $workflowStartTime = [DateTime]::Parse($StartTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    }

    $workflowDuration = $EndTime.ToUniversalTime().Subtract($workflowStartTime).TotalSeconds
    return $workflowDuration
}

Export-ModuleMember -Function GetWorkflowDuration
