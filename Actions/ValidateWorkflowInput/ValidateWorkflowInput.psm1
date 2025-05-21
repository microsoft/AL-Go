<#
 .DESCRIPTION
  This module contains functions to validate input values for the workflow.
  The functions are called from the workflow to validate the inputs.
#>


<#
  Validates the version number input for the workflow.
  The version number must be a valid version number or a relative version number.
  The version number can have 2 or 3 segments, depending on the versioning strategy.
  The function checks if the version number is in the correct format and throws an error if it is not.
#>
function Validate-UpdateVersionNumber {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings,
        [Parameter(Mandatory = $true)]
        [string] $inputName,
        [Parameter(Mandatory = $true)]
        [string] $inputValue
    )

    $strategy3 = (($settings.versioningStrategy -band 15) -eq 3)
    $legalRelativeValues = @('+1','+0.1')
    if ($strategy3) {
        $legalRelativeValues += @('+0.0.1')
    }
    $errorMessage = "$inputName is '$inputValue', must be a version number with $(2+[int]$strategy3) segments or one of: $($legalRelativeValues -join ', ')"
    if ($inputValue.StartsWith('+')) {
        # Relative version number
        if ($legalRelativeValues -notcontains $inputValue) {
            throw $errorMessage
        }
    }
    else {
        # Absolute version number
        try {
            $versionNumber = [System.Version]::Parse($inputValue)
        }
        catch {
            throw $errorMessage
        }
        if (($versionNumber.Revision -ne -1) -or (!$strategy3 -and ($versionNumber.Build -ne -1))) {
            throw $errorMessage
        }
        if ($strategy3 -and $versionNumber.Build -eq -1) {
            throw $errorMessage
        }
    }
}

Export-ModuleMember *-*
