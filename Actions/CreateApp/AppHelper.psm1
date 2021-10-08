<#
This module contains some useful functions for working with app manifests.
#>

. (Join-Path -path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

# function GetManifest
# (
# ) {

# }

$validRanges = @{
    "PTE"           = "50000..99999";
    "AppSource App" = "100000..$([int32]::MaxValue)";
    "Test App"      = "50000..$([int32]::MaxValue)" ;
};

function ValidateIdRanges([string] $templateType, [string]$idrange ) {  
    $validRange = $validRanges.$templateType.Replace('..', '-').Split("-")
    $validStart = [int](stringToInt($validRange[0]))
    $validEnd = [int](stringToInt($validRange[1]))

    $ids = $idrange.Replace('..', '-').Split("-")
    $idStart = [int](stringToInt($ids[0]))
    $idEnd = [int](stringToInt($ids[1]))
    
    if ($ids.Count -ne 2 -or ($idStart) -lt $validStart -or $idStart -gt $idEnd -or $idEnd -lt $validStart -or $idEnd -gt $validEnd -or $idStart -gt $idEnd) 
    { 
        throw "IdRange should be formattet as fromId..toId, and the Id range must be in $($validRange[0]) and $($validRange[1])"
    }

    return $ids
} 

<#
.SYNOPSIS
Creates a simple PTE.
#>
function CreateSimplePTE
(
    [string]$idrange
) 
{

}

# <#
# .SYNOPSIS
# Creates an AppSource app.
# #>
# function CreateSimpleAppSource App
# (
#     [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $True)]
#     [psobject]$ChangeSet,
#     [string]$ClientName
# ) {

# }

# <#
# .SYNOPSIS
# Creates a test app.
# #>
# function CreateSimpleTestApp
# (
#     [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $True)]
#     [psobject]$ChangeSet,
#     [string]$ClientName
# ) {

# }


# Export-ModuleMember -Function CreateSimplePTE
# Export-ModuleMember -Function CreateSimpleAppSource App
Export-ModuleMember -Function ValidateIdRanges
