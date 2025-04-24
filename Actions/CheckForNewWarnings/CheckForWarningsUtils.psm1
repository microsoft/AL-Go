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
        [string] $prBuild,
        [switch] $treatAsErrors
    )

    $refWarnings =  @(Get-Warnings -BuildFile $referenceBuild)
    $prWarnings = @(Get-Warnings -BuildFile $prBuild)

    Write-Host "Found $($refWarnings.Count) warnings in reference build."
    Write-Host "Found $($prWarnings.Count) warnings in PR build."   

    Compare-Object -ReferenceObject $refWarnings -DifferenceObject $prWarnings -Property Id,File,Description,Line,Col -PassThru | 
        Where-Object { $_.SideIndicator -eq "=>" } | 
        Select-Object -Property Id,File,Description,Line,Col | ForEach-Object {

            Write-Host "::error::file=$($_.File),line=$($_.Line),col=$($_.Col)::New warning introduced in this PR: $($_.Id) $($_.Description)"

        }    
}


Export-ModuleMember -Function Initialize-Directory
Export-ModuleMember -Function Get-Warnings
Export-ModuleMember -Function Compare-Files