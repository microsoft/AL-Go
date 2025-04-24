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
            if ($_  -match "Warning: ([A-Z]{2}[0-9]{4}) (.+)")
            {
                $warnings += New-Object -Type PSObject -Property @{
                    Id = $Matches[1]
                    Description = $Matches[2]
                }
            }
        }
    }

    return $warnings
}


Export-ModuleMember -Function Initialize-Directory
Export-ModuleMember -Function Get-Warnings