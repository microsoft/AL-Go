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


Export-ModuleMember -Function Initialize-Directory
Export-ModuleMember -Function Get-Warnings