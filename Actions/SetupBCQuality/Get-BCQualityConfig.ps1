<#
.SYNOPSIS
    Loads and validates the tracked BCQuality plugin policy.

.DESCRIPTION
    Returns the internal policy used to filter an installed BCQuality plugin
    and construct agent task context. Marketplace repository and content
    version are supplied separately through AL-Go's BCQuality settings.

    Requires the powershell-yaml module. Workflows that consume this script
    install it before invoking.

.PARAMETER ConfigPath
    Path to bcquality.config.yaml. Defaults to the policy beside this script.
#>
[CmdletBinding()]
param(
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'bcquality.config.yaml'
}

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    throw "powershell-yaml module is required. Install with: Install-Module powershell-yaml -Scope CurrentUser -Force"
}
Import-Module powershell-yaml -DisableNameChecking -ErrorAction Stop

if (-not (Test-Path $ConfigPath)) {
    throw "bcquality config not found: $ConfigPath"
}

function ConvertTo-Mutable {
    # powershell-yaml returns ordered dictionaries and Object[] arrays.
    # Normalize into plain hashtables and List[object] so we can mutate
    # cleanly and keep single-element arrays from getting unwrapped.
    param([object] $Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $Value.Keys) { $h[$k] = ConvertTo-Mutable $Value[$k] }
        return $h
    }
    if ($Value -is [System.Collections.IList] -and -not ($Value -is [string])) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $list.Add((ConvertTo-Mutable $item)) | Out-Null }
        return ,$list
    }
    return $Value
}

function ConvertTo-ObjectList {
    param([object] $Value)
    if ($null -eq $Value) { return [System.Collections.Generic.List[object]]::new() }
    if ($Value -is [System.Collections.Generic.List[object]]) { return $Value }
    $list = [System.Collections.Generic.List[object]]::new()
    if ($Value -is [System.Collections.IList] -and -not ($Value -is [string])) {
        foreach ($item in $Value) { $list.Add($item) | Out-Null }
    } else {
        $list.Add($Value) | Out-Null
    }
    return $list
}

$raw = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
$parsed = ConvertFrom-Yaml -Yaml $raw -Ordered

$cfg = ConvertTo-Mutable $parsed
if ($null -eq $cfg -or -not ($cfg -is [hashtable])) {
    throw "bcquality.config.yaml did not parse to a mapping at the top level."
}

# Defaults for any missing keys so downstream code never sees them missing.
if (-not $cfg.ContainsKey('plugin-version')) {
    $cfg['plugin-version'] = '0.2.0'
}

$cfg['enabled-layers']  = ConvertTo-ObjectList ($cfg['enabled-layers']  ?? @('microsoft'))
$cfg['disabled-skills'] = ConvertTo-ObjectList ($cfg['disabled-skills'] ?? @())

if (-not $cfg.ContainsKey('knowledge') -or -not ($cfg['knowledge'] -is [hashtable])) {
    $cfg['knowledge'] = @{}
}
$cfg['knowledge']['allow'] = ConvertTo-ObjectList ($cfg['knowledge']['allow'] ?? @())
$cfg['knowledge']['deny']  = ConvertTo-ObjectList ($cfg['knowledge']['deny']  ?? @())

if (-not $cfg.ContainsKey('task-context') -or -not ($cfg['task-context'] -is [hashtable])) {
    $cfg['task-context'] = @{}
}

# Validate enabled-layers against the known layer set; reject typos early.
$knownLayers = @('microsoft', 'community', 'custom')
foreach ($layer in $cfg['enabled-layers']) {
    if ($knownLayers -notcontains $layer) {
        throw "Unknown enabled-layers value: '$layer'. Allowed: $($knownLayers -join ', ')"
    }
}

if ([string]::IsNullOrWhiteSpace([string]$cfg['plugin-version'])) {
    throw 'plugin-version must be specified.'
}

return $cfg
