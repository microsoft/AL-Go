Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Name of the override to run", Mandatory = $true)]
    [string] $overrideName,
    [Parameter(HelpMessage = "Compressed JSON string with parameters to pass to the override script", Mandatory = $false)]
    [string] $parametersJson = '{}'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$parameters = @{}
if ($parametersJson) {
    try {
        $parsed = $parametersJson | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse parametersJson as JSON: $($_.Exception.Message)"
    }
    if ($null -ne $parsed) {
        if ($parsed -isnot [System.Management.Automation.PSCustomObject]) {
            throw "parametersJson must deserialize to a JSON object, not $($parsed.GetType().Name)."
        }
        $parameters = ConvertTo-HashTable $parsed -recurse
    }
}

Invoke-ALGoOverride -Project $project -OverrideName $overrideName -Parameters $parameters
