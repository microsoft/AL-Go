# Shared utility functions for CoverageProcessor modules.
# Dot-sourced by CoberturaFormatter.psm1 and CoverageProcessor.psm1.

<#
    .SYNOPSIS
    Safely checks if a property exists on a hashtable or PSCustomObject under strict mode.

    .PARAMETER InputObject
    The object to check. Can be a hashtable, PSCustomObject, or $null.

    .PARAMETER PropertyName
    The name of the property to look for.
#>
function Test-PropertyExists {
    param($InputObject, [string]$PropertyName)
    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [hashtable]) { return $InputObject.ContainsKey($PropertyName) }
    return $null -ne $InputObject.PSObject.Properties[$PropertyName]
}
