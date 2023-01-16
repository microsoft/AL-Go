<#
This module contains some useful functions for working with app manifests.
#>

. (Join-Path -path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$alTemplatePath = Join-Path -Path $here -ChildPath "AppTemplate" 


$validRanges = @{
    "PTE"                  = "50000..99999";
    "AppSource App"        = "100000..$([int32]::MaxValue)";
    "Test App"             = "50000..$([int32]::MaxValue)" ;
    "Performance Test App" = "50000..$([int32]::MaxValue)" ;
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
    [string] $sourceFolder = $alTemplatePath,
    [string] $appJsonFile,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange,
    [switch] $AddTestDependencies
) 
{
    #Modify app.json
    $appJson = Get-Content (Join-Path $sourceFolder "app.json") -Encoding UTF8 | ConvertFrom-Json

    $appJson.id = [Guid]::NewGuid().ToString()
    $appJson.Publisher = $publisher
    $appJson.Name = $name
    $appJson.Version = $version
    $appJson.Logo = ""
    $appJson.url = ""
    $appJson.EULA = ""
    $appJson.privacyStatement = ""
    $appJson.help = ""
    "contextSensitiveHelpUrl" | ForEach-Object {
        if ($appJson.PSObject.Properties.Name -eq $_) { $appJson.PSObject.Properties.Remove($_) }
    }
    $appJson.idRanges[0].from = [int]$idrange[0]
    $appJson.idRanges[0].to = [int]$idrange[1]
    if ($AddTestDependencies) {
        $appJson.dependencies += @(
            @{
                "id" = "dd0be2ea-f733-4d65-bb34-a28f4624fb14"
                "publisher" = "Microsoft"
                "name" = "Library Assert"
                "version" = $appJson.Application
            },
            @{
                "id" = "e7320ebb-08b3-4406-b1ec-b4927d3e280b"
                "publisher" = "Microsoft"
                "name" = "Any"
                "version" = $appJson.Application
            }
        )

    }
    $appJson | Set-JsonContentLF -path $appJsonFile
}

function UpdateALFile 
(
    [string] $sourceFolder = $alTemplatePath,
    [string] $destinationFolder,
    [string] $alFileName,
    [int] $fromId = 50100,
    [int] $toId = 50100,
    [int] $startId
) 
{
    $al = Get-Content -Encoding UTF8 -Raw -path (Join-Path $sourceFolder $alFileName)
    $fromId..$toId | ForEach-Object {
        $al = $al.Replace("$_", $startId)
        $startId++
    }
    $al | Set-ContentLF -Path (Join-Path $destinationFolder $alFileName)
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
    [string[]] $idrange,
    [bool] $sampleCode
) 
{
    Write-Host "Creating a new sample app in: $destinationPath"
    New-Item  -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item  -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    Copy-Item -path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version
    if ($sampleCode) {
        UpdateALFile -destinationFolder $destinationPath -alFileName "HelloWorld.al" -startId $idrange[0]
    }
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
    [string[]] $idrange,
    [bool] $sampleCode
) 
{
    Write-Host "Creating a new test app in: $destinationPath"
    New-Item  -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item  -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    Copy-Item -path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version -AddTestDependencies
    if ($sampleCode) {
        UpdateALFile -destinationFolder $destinationPath -alFileName "HelloWorld.Test.al" -startId $idrange[0]
    }
}

# <#
# .SYNOPSIS
# Creates a performance test app.
# #>
function New-SamplePerformanceTestApp
(
    [string] $destinationPath,
    [string] $name,
    [string] $publisher,
    [string] $version,
    [string[]] $idrange,
    [bool] $sampleCode,
    [bool] $sampleSuite,
    [string] $appSourceFolder
) 
{
    Write-Host "Creating a new performance test app in: $destinationPath"
    New-Item  -Path $destinationPath -ItemType Directory -Force | Out-Null
    New-Item  -Path "$($destinationPath)\.vscode" -ItemType Directory -Force | Out-Null
    New-Item  -Path "$($destinationPath)\src" -ItemType Directory -Force | Out-Null
    Copy-Item -path "$($alTemplatePath)\.vscode\launch.json" -Destination "$($destinationPath)\.vscode\launch.json"

    UpdateManifest -sourceFolder $appSourceFolder -appJsonFile "$($destinationPath)\app.json" -name $name -publisher $publisher -idrange $idrange -version $version

    if ($sampleCode) {
        Get-ChildItem -Path "$appSourceFolder\src" -Recurse -Filter "*.al" | ForEach-Object {
            Write-Host $_.Name
            UpdateALFile -sourceFolder $_.DirectoryName -destinationFolder "$($destinationPath)\src" -alFileName $_.name -fromId 149100 -toId 149200 -startId $idrange[0]
        }
    }
    if ($sampleSuite) {
        UpdateALFile -sourceFolder $alTemplatePath -destinationFolder $destinationPath -alFileName bcptSuite.json -fromId 149100 -toId 149200 -startId $idrange[0]
    }
}

function Update-WorkSpaces 
(
    [string] $projectFolder,
    [string] $appName
) 
{
    Get-ChildItem -Path $projectFolder -Filter "*.code-workspace" | 
        ForEach-Object {
            try {
                $workspaceFileName = $_.Name
                $workspaceFile = $_.FullName
                $workspace = Get-Content $workspaceFile -Encoding UTF8 | ConvertFrom-Json
                if (-not ($workspace.folders | Where-Object { $_.Path -eq $appName })) {
                    $workspace.folders += @(@{ "path" = $appName })
                }
                $workspace | Set-JsonContentLF -Path $workspaceFile
            }
            catch {
                throw "Updating the workspace file $workspaceFileName failed.$([environment]::Newline) $($_.Exception.Message)"
            }
        }
}

Export-ModuleMember -Function New-SampleApp
Export-ModuleMember -Function New-SampleTestApp
Export-ModuleMember -Function New-SamplePerformanceTestApp
Export-ModuleMember -Function Confirm-IdRanges
Export-ModuleMember -Function Update-WorkSpaces
