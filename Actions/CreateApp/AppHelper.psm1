<#
This module contains some useful functions for working with app manifests.
#>

. (Join-Path -path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$alTemplatePath = Join-Path -Path $here -ChildPath "AppTemplate" 


$validRanges = @{
    "PTE"           = "50000..99999";
    "AppSource App" = "100000..$([int32]::MaxValue)";
    "Test App"      = "50000..$([int32]::MaxValue)" ;
};

function Confirm-IdRanges([string] $templateType, [string]$idrange ) {  
    $validRange = $validRanges.$templateType.Replace('..', '-').Split("-")
    $validStart = [int] $validRange[0]
    $validEnd = [int] $validRange[1]

    $ids = $idrange.Replace('..', '-').Split("-")
    $idStart = [int] $ids[0]
    $idEnd = [int] $ids[1]
    
    if ($ids.Count -ne 2 -or ($idStart) -lt $validStart -or $idStart -gt $idEnd -or $idEnd -lt $validStart -or $idEnd -gt $validEnd -or $idStart -gt $idEnd) { 
        throw "IdRange should be formatted as fromId..toId, and the Id range must be in $($validRange[0]) and $($validRange[1])"
    }

    return $ids
} 

function UpdateManifest
(
    [string] $appJsonFile,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange
) 
{
    #Modify app.json
    $appJson = Get-Content "$($alTemplatePath)\app.json" -Encoding UTF8 | ConvertFrom-Json

    $appJson.id = [Guid]::NewGuid().ToString()
    $appJson.Publisher = $publisher
    $appJson.Name = $name
    $appJson.Version = $version
    $appJson.idRanges[0].from = [int]$idrange[0]
    $appJson.idRanges[0].to = [int]$idrange[1]
    $appJson | ConvertTo-Json -depth 99 | Set-Content $appJsonFile -Encoding UTF8
}

function UpdateALFile 
(
    [string] $destinationFolder,
    [string] $alFileName,
    [string] $startId
) 
{
    $al = Get-Content -Encoding UTF8 -Raw -path "$($alTemplatePath)\$alFileName"
    $al = $al.Replace('50100', $startId)
    Set-Content -Path "$($destinationFolder)\$($alFileName)" -value $al -Encoding UTF8
}

<#
.SYNOPSIS
Creates a simple app.
#>
function New-SampleApp
(
    [string] $destinationPath,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange
) 
{
    Write-Host "Creating a new sample app in: $destinationPath"
    New-Item  -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item  -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    Copy-Item -path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version
    UpdateALFile -destinationFolder $destinationPath -alFileName "HelloWorld.al" -startId $idrange[0]
}


# <#
# .SYNOPSIS
# Creates a test app.
# #>
function New-SampleTestApp
(
    [string] $destinationPath,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange
) 
{
    Write-Host "Creating a new test app in: $destinationPath"
    New-Item  -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item  -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    Copy-Item -path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version
    UpdateALFile -destinationFolder $destinationPath -alFileName "HelloWorld.Test.al" -startId $idrange[0]
}

function Update-WorkSpaces 
(
    [string] $baseFolder,
    [string] $appName
) 
{
    Get-ChildItem -Path $baseFolder -Filter "*.code-workspace" | 
        ForEach-Object {
            try {
                $workspaceFileName = $_.Name
                $workspaceFile = $_.FullName
                $workspace = Get-Content $workspaceFile -Encoding UTF8 | ConvertFrom-Json
                if (-not ($workspace.folders | Where-Object { $_.Path -eq $appName })) {
                    $workspace.folders += @(@{ "path" = $appName })
                }
                $workspace | ConvertTo-Json -Depth 99 | Set-Content -Path $workspaceFile -Encoding UTF8
            }
            catch {
                throw "Updating the workspace file $workspaceFileName failed.$([environment]::Newline) $($_.Exception.Message)"
            }
        }
}

Export-ModuleMember -Function New-SampleApp
Export-ModuleMember -Function New-SampleTestApp
Export-ModuleMember -Function Confirm-IdRanges
Export-ModuleMember -Function Update-WorkSpaces