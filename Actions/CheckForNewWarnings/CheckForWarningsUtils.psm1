<#
    .SYNOPSIS
    Ensures that a specified directory exists. If the directory does not exist, it creates it.
    .DESCRIPTION
    Ensures that a specified directory exists. If the directory does not exist, it creates it.
#>
function Initialize-Directory
{
    [CmdletBinding()]
    param (
        [string] $Path
    )

    if (!(Test-Path $Path))
    {
        New-Item -Path $Path -ItemType Directory | Out-Null
    }
}

<#
    .SYNOPSIS
    This function parses a build log file and returns the AL warnings found in it.
    .DESCRIPTION
    This function parses a build log file and returns the AL warnings found in it.
#>
function Get-Warnings
{
    [CmdletBinding()]
    param (
        [string] $BuildFile
    )

    $warnings = @()

    if (Test-Path $BuildFile)
    {
        Get-Content $BuildFile | ForEach-Object {
            if ($_  -match "::warning file=(.+),line=([0-9]{1,5}),col=([0-9]{1,5})::([A-Z]{2}[0-9]{4}) (.+)")
            {
                $warnings += New-Object -Type PSObject -Property @{
                    Id = $Matches[4]
                    File= $Matches[1]
                    Description = $Matches[5]
                    Line = $Matches[2]
                    Col = $Matches[3]
                }
            }
        }
    }

    return $warnings
}

function Compare-Files
{
    [CmdletBinding()]
    param (
        [string] $referenceBuild,
        [string] $prBuild
    )

    $refWarnings =  @(Get-Warnings -BuildFile $referenceBuild)
    $prWarnings = @(Get-Warnings -BuildFile $prBuild)

    Write-Host "Found $($refWarnings.Count) warnings in reference build."
    Write-Host "Found $($prWarnings.Count) warnings in PR build."   

    $delta = Compare-Object -ReferenceObject $refWarnings -DifferenceObject $prWarnings -Property Id,File,Description,Col -PassThru | 
        Where-Object { $_.SideIndicator -eq "=>" } | 
        Select-Object -Property Id,File,Description,Line,Col 

    $delta | ForEach-Object {
            Write-Host "::error file=$($_.File),line=$($_.Line),col=$($_.Col)::New warning introduced in this PR: [$($_.Id)] $($_.Description)"
        }

    if ($delta)
    {
        throw "New warnings were introduced in this PR."
    }
}

Export-ModuleMember -Function Initialize-Directory
Export-ModuleMember -Function Compare-Files