Param(
    [string] $path
)

# This script is launched using pwsh when running PowerShell 5.1 to format JSON files like PowerShell 7 does.
# See function Set-JsonContentLF in Actions\GitHubHelper.ps1
$content = Get-Content $path -Encoding UTF8 | ConvertFrom-Json | ConvertTo-Json -Depth 99
$content = $content.Replace("`r", "")
$content | Out-Host
[System.IO.File]::WriteAllText($path, "$content`n")
