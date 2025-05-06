. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
 .DESCRIPTION
  This module contains functions to validate input values for the workflow.
  The functions are called from the workflow to validate the inputs.
#>


<#
#>
function Test-UpdateVersionNumber {
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
    $errorMessage = "Must be a version number with $(2+[int]$strategy3) segments or one of: $($legalRelativeValues -join ', ')"
    if ($inputValue.StartsWith('+')) {
        # Relative version number
        if ($legalValues -notcontains $inputValue) {
            return $errorMessage
        }
    }
    else {
        # Absolute version number
        try {
            $versionNumber = [System.Version]::Parse($inputValue)
        }
        catch {
            return $errorMessage
        }
        if (($versionNumber.Revision -ne -1) -or (!$strategy3 -and ($versionNumber.Build -ne -1))) {
            return $errorMessage
        }
    }
}

Export-ModuleMember *-*
