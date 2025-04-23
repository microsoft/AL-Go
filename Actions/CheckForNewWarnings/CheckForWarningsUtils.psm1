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

Export-ModuleMember -Function Initialize-Directory
