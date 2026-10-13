Set-StrictMode -Version 2.0

<#
.SYNOPSIS
Converts a comma-separated setting into trimmed values.

.PARAMETER Value
The comma-separated value to convert.

.OUTPUTS
An array containing the non-empty trimmed values.
#>
function ConvertFrom-CsvSetting {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

<#
.SYNOPSIS
Tests a normalized plugin path against a Git-style glob.

.PARAMETER Path
The forward-slash plugin-relative path to test.

.PARAMETER Pattern
The Git-style glob pattern to match.

.OUTPUTS
True when the path matches the pattern; otherwise false.
#>
function Test-GlobMatch {
    param(
        [string] $Path,
        [string] $Pattern
    )

    $normalizedPattern = ($Pattern -replace '\\', '/').Trim()
    if (-not $normalizedPattern) {
        return $false
    }

    $regex = [System.Text.StringBuilder]::new()
    [void] $regex.Append('^')
    for ($index = 0; $index -lt $normalizedPattern.Length; $index++) {
        $character = $normalizedPattern[$index]
        if ($character -eq '*' -and ($index + 1) -lt $normalizedPattern.Length -and $normalizedPattern[$index + 1] -eq '*') {
            [void] $regex.Append('.*')
            $index++
            if (($index + 1) -lt $normalizedPattern.Length -and $normalizedPattern[$index + 1] -eq '/') {
                $index++
            }
        }
        elseif ($character -eq '*') {
            [void] $regex.Append('[^/]*')
        }
        elseif ($character -eq '?') {
            [void] $regex.Append('[^/]')
        }
        elseif (@('.', '\', '+', '(', ')', '{', '}', '[', ']', '^', '$', '|') -contains $character) {
            [void] $regex.Append('\').Append($character)
        }
        else {
            [void] $regex.Append($character)
        }
    }
    [void] $regex.Append('$')
    return $Path -match $regex.ToString()
}

<#
.SYNOPSIS
Gets a forward-slash relative path within the installed plugin.

.PARAMETER Root
The installed plugin root.

.PARAMETER FullName
The full path to a file within the plugin root.

.OUTPUTS
The plugin-relative path using forward slashes.
#>
function Get-RelativePluginPath {
    param(
        [string] $Root,
        [string] $FullName
    )

    return ($FullName.Substring($Root.Length).TrimStart([char] '/', [char] '\') -replace '\\', '/')
}

<#
.SYNOPSIS
Resolves a plugin-relative path and rejects traversal outside the plugin root.

.PARAMETER Root
The installed plugin root.

.PARAMETER RelativePath
The plugin-relative path to resolve.

.OUTPUTS
The resolved full path within the plugin root.
#>
function Resolve-SafePluginPath {
    param(
        [string] $Root,
        [string] $RelativePath
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $RelativePath))
    $prefix = "$resolvedRoot$([System.IO.Path]::DirectorySeparatorChar)"
    if (-not $resolvedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "BCQuality path '$RelativePath' escapes the installed plugin root."
    }
    return $resolvedPath
}

<#
.SYNOPSIS
Reads Copilot configuration while tolerating a UTF-8 byte-order mark.

.PARAMETER Path
The path to the Copilot configuration file.

.OUTPUTS
The parsed Copilot configuration object.
#>
function Read-CopilotConfig {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Copilot plugin configuration not found: $Path"
    }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $jsonStart = $raw.IndexOf('{')
    if ($jsonStart -lt 0) {
        throw "Copilot plugin configuration is malformed: $Path"
    }
    try {
        return $raw.Substring($jsonStart) | ConvertFrom-Json
    }
    catch {
        throw "Copilot plugin configuration is malformed: $Path"
    }
}

<#
.SYNOPSIS
Calculates the deterministic hash of retained BCQuality content.

.PARAMETER Root
The installed and filtered BCQuality plugin root.

.OUTPUTS
The lowercase SHA-256 hash of retained plugin content.
#>
function Get-FilteredContentHash {
    param([string] $Root)

    $lines = foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $relativePath = Get-RelativePluginPath -Root $Root -FullName $file.FullName
        if ($relativePath -in @('_filter-report.json', '_skill-index.json', 'knowledge-index.json')) {
            continue
        }

        $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relativePath`0$fileHash"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

<#
.SYNOPSIS
Runs child processes with temporary GitHub HTTP authentication.

.DESCRIPTION
The token is exposed only through process-scoped Git configuration environment
variables for non-default marketplaces. The previous values are restored before
the function returns.

.PARAMETER Repository
The GitHub marketplace repository in owner/repository form.

.PARAMETER Token
The GitHub token to use for HTTPS Git operations.

.PARAMETER ScriptBlock
The child-process operations that require authentication.

.OUTPUTS
The output produced by the script block.
#>
function Invoke-WithGitHubToken {
    param(
        [Parameter(Mandatory)]
        [string] $Repository,
        [string] $Token,
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    if ($Repository -ieq 'microsoft/BCQuality' -or [string]::IsNullOrWhiteSpace($Token)) {
        return & $ScriptBlock
    }

    $variableNames = @('GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0')
    $previous = @{}
    foreach ($name in $variableNames) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }

    $credentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$Token"))
    try {
        $env:GIT_CONFIG_COUNT = '1'
        $env:GIT_CONFIG_KEY_0 = 'http.https://github.com/.extraheader'
        $env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $credentials"
        return & $ScriptBlock
    }
    finally {
        foreach ($name in $variableNames) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

<#
.SYNOPSIS
Resolves a GitHub marketplace branch or tag to a commit SHA.

.PARAMETER Repository
The GitHub repository in owner/repository form.

.PARAMETER Ref
The branch or tag to resolve.

.OUTPUTS
The resolved 40-character commit SHA.
#>
function Resolve-MarketplaceCommit {
    param(
        [string] $Repository,
        [string] $Ref
    )

    $remoteUrl = "https://github.com/$Repository.git"
    $lines = @(& git ls-remote $remoteUrl "refs/tags/$Ref" "refs/tags/$Ref^{}" "refs/heads/$Ref")
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve BCQuality marketplace ref '$Repository#$Ref'."
    }

    $resolved = @{}
    foreach ($line in $lines) {
        if ($line -match '^([0-9a-f]{40})\s+(.+)$') {
            $resolved[$Matches[2]] = $Matches[1]
        }
    }
    if ($resolved.ContainsKey("refs/tags/$Ref^{}")) {
        return $resolved["refs/tags/$Ref^{}"]
    }
    if ($resolved.ContainsKey("refs/tags/$Ref")) {
        return $resolved["refs/tags/$Ref"]
    }
    if ($resolved.ContainsKey("refs/heads/$Ref")) {
        return $resolved["refs/heads/$Ref"]
    }
    throw "BCQuality marketplace ref '$Repository#$Ref' did not resolve to a branch or tag."
}

Export-ModuleMember -Function ConvertFrom-CsvSetting, Test-GlobMatch, Get-RelativePluginPath, Resolve-SafePluginPath, Read-CopilotConfig, Get-FilteredContentHash, Invoke-WithGitHubToken, Resolve-MarketplaceCommit
