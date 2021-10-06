<#
This module contains some useful functions for working with app manifests.
#>

function GetManifest
(
)
{

}


<#
.SYNOPSIS
Creates a simple PTE.
#>
function CreateSimplePTE
(
    [Parameter(Position = 0,Mandatory = $false,ValueFromPipeline=$True)]
    [psobject]$ChangeSet,
    [string]$ClientName
) 
{

}

<#
.SYNOPSIS
Creates an AppSource app.
#>
function CreateSimpleAppSourceApp
(
    [Parameter(Position = 0,Mandatory = $false,ValueFromPipeline=$True)]
    [psobject]$ChangeSet,
    [string]$ClientName
) 
{

}

<#
.SYNOPSIS
Creates a test app.
#>
function CreateSimpleTestApp
(
    [Parameter(Position = 0,Mandatory = $false,ValueFromPipeline=$True)]
    [psobject]$ChangeSet,
    [string]$ClientName
) 
{

}


Export-ModuleMember -Function CreateSimplePTE
Export-ModuleMember -Function CreateSimpleAppSourceApp
