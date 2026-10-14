# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------
function Invoke-GitCommand {
    param([string[]] $Arguments)

    $output = @(& git @Arguments 2>&1 | ForEach-Object { "$($_)" })
    if ($LASTEXITCODE -ne 0) {
        $argsText = ($Arguments -join ' ')
        $details = ($output -join "`n")
        throw "git command failed (exit $LASTEXITCODE): git $argsText`n$details"
    }
    return $output
}

function New-GitProcess {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        $process.Dispose()
        throw "Failed to start git $($Arguments -join ' ')."
    }
    return $process
}

function Invoke-GitCommandBytes {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $process = New-GitProcess -Arguments $Arguments
    try {
        $process.StandardInput.Close()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $output = [IO.MemoryStream]::new()
        try {
            $process.StandardOutput.BaseStream.CopyTo($output)
            $process.WaitForExit()
            $details = $errorTask.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) {
                throw "git command failed (exit $($process.ExitCode)): git $($Arguments -join ' ')`n$details"
            }
            return ,$output.ToArray()
        }
        finally {
            $output.Dispose()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Read-GitProtocolLine {
    param([Parameter(Mandatory)][IO.Stream] $Stream)

    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($true) {
        $value = $Stream.ReadByte()
        if ($value -lt 0) {
            throw 'Unexpected end of output from git cat-file.'
        }
        if ($value -eq 10) {
            return [Text.Encoding]::ASCII.GetString($bytes.ToArray())
        }
        $bytes.Add([byte]$value)
    }
}

function Copy-StreamBytes {
    param(
        [Parameter(Mandatory)][IO.Stream] $InputStream,
        [Parameter(Mandatory)][IO.Stream] $OutputStream,
        [Parameter(Mandatory)][long] $Count
    )

    $buffer = [byte[]]::new(81920)
    $remaining = $Count
    while ($remaining -gt 0) {
        $read = $InputStream.Read($buffer, 0, [Math]::Min($buffer.Length, $remaining))
        if ($read -le 0) {
            throw "Unexpected end of git blob after $($Count - $remaining) of $Count bytes."
        }
        $OutputStream.Write($buffer, 0, $read)
        $remaining -= $read
    }
}

# Runs a git command with an ephemeral, host-scoped credential so that fetches
# against a PRIVATE target repo succeed. The workflow checks out the target with
# persist-credentials:false (no token in .git/config, where an injected Copilot
# tool-call could read it), so we inject the token per-invocation via git's
# GIT_CONFIG_* environment override instead. The token never touches .git/config
# or the process command line, and is removed as soon as the command returns.
function Invoke-GitCommandAuthenticated {
    param([string[]] $Arguments)

    # The generate phase carries GH_TOKEN; the post phase carries GITHUB_TOKEN.
    # Either can authenticate a contents:read fetch, so use whichever is present.
    $token = if ($CopilotToken) { $CopilotToken } else { $GithubToken }
    if (-not $token) {
        return Invoke-GitCommand -Arguments $Arguments
    }

    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = "http.$GitHubServerUrl/.extraheader"
    $env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $basic"
    try {
        return Invoke-GitCommand -Arguments $Arguments
    }
    finally {
        Remove-Item Env:GIT_CONFIG_COUNT, Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue
    }
}

function Get-PathSpecArgs {
    if (-not $ReviewPathSpec) { return @() }
    $specs = @($ReviewPathSpec -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $specs) { return @() }
    return @('--') + $specs
}

function Get-GitChangedFiles {
    $gitArgs = @('-C', $AnalysisWorkspace, 'diff', '--name-only', '-z', $DiffRange) + (Get-PathSpecArgs)
    $output = Invoke-GitCommand -Arguments $gitArgs
    return @(($output -join "`n") -split "`0" | Where-Object { $_ })
}

function Get-GitFilePatch {
    param([string] $FilePath)
    # Path-scoped diff for a specific file. The pathspec above is only used
    # to narrow the changed-files list; per-file diffs remain unscoped so we
    # still get the full patch for each surviving file.
    $output = Invoke-GitCommand -Arguments @('-C', $AnalysisWorkspace, 'diff', $DiffRange, '--', $FilePath)
    return ($output -join "`n")
}

function New-ReviewDataProjection {
    if (Test-Path -LiteralPath $ReviewDataRoot) {
        Remove-Item -LiteralPath $ReviewDataRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $ReviewDataRoot -Force | Out-Null

    # Read blobs directly from Git's object database. Unlike git archive or a
    # checkout, cat-file does not honor PR-controlled attributes such as
    # export-ignore, export-subst, or content filters.
    $listingBytes = Invoke-GitCommandBytes -Arguments @(
        '-C', $AnalysisWorkspace, 'ls-tree', '-r', '-z', '--full-tree', 'HEAD'
    )
    $entries = [Text.Encoding]::UTF8.GetString($listingBytes).Split(
        [char]0,
        [StringSplitOptions]::RemoveEmptyEntries
    )
    $blobEntries = [System.Collections.Generic.List[object]]::new()
    $projectionRoot = [IO.Path]::GetFullPath($ReviewDataRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $projectionPrefix = $projectionRoot + [IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }

    foreach ($entry in $entries) {
        $tabIndex = $entry.IndexOf("`t", [StringComparison]::Ordinal)
        if ($tabIndex -lt 0) {
            throw "Unexpected git ls-tree entry: '$entry'."
        }
        $metadata = $entry.Substring(0, $tabIndex).Split(' ')
        if ($metadata.Count -ne 3) {
            throw "Unexpected git ls-tree metadata: '$($entry.Substring(0, $tabIndex))'."
        }
        if ($metadata[1] -ne 'blob') {
            continue
        }

        $relativePath = $entry.Substring($tabIndex + 1)
        $destination = [IO.Path]::GetFullPath(
            (Join-Path $projectionRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar))
        )
        if (-not $destination.StartsWith($projectionPrefix, $pathComparison)) {
            throw "Refusing to project Git path outside the review data root: '$relativePath'."
        }
        $blobEntries.Add([pscustomobject]@{
            ObjectId = $metadata[2]
            Path = $destination
        })
    }

    if ($blobEntries.Count -gt 0) {
        $process = New-GitProcess -Arguments @('-C', $AnalysisWorkspace, 'cat-file', '--batch')
        try {
            $errorTask = $process.StandardError.ReadToEndAsync()
            foreach ($blob in $blobEntries) {
                $process.StandardInput.WriteLine($blob.ObjectId)
                $process.StandardInput.Flush()

                $header = Read-GitProtocolLine -Stream $process.StandardOutput.BaseStream
                if ($header -notmatch '\A(?<oid>[0-9a-f]+) blob (?<size>\d+)\z' -or
                    $Matches.oid -ne $blob.ObjectId) {
                    throw "Unexpected git cat-file response for '$($blob.ObjectId)': '$header'."
                }

                $parent = Split-Path -Parent $blob.Path
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                $output = [IO.File]::Open(
                    $blob.Path,
                    [IO.FileMode]::CreateNew,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::None
                )
                try {
                    Copy-StreamBytes `
                        -InputStream $process.StandardOutput.BaseStream `
                        -OutputStream $output `
                        -Count ([long]$Matches.size)
                }
                finally {
                    $output.Dispose()
                }
                if ($process.StandardOutput.BaseStream.ReadByte() -ne 10) {
                    throw "Missing delimiter after Git blob '$($blob.ObjectId)'."
                }
            }

            $process.StandardInput.Close()
            $process.WaitForExit()
            $details = $errorTask.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) {
                throw "git cat-file failed (exit $($process.ExitCode)):`n$details"
            }
        }
        finally {
            if (-not $process.HasExited) {
                $process.Kill($true)
                $process.WaitForExit()
            }
            $process.Dispose()
        }
    }

    $trustedConfigurationPaths = @(
        '.github/skills',
        '.github/agents',
        '.github/instructions',
        '.github/copilot-instructions.md',
        '.agents/skills',
        '.claude/skills',
        'AGENTS.md',
        'CLAUDE.md',
        'GEMINI.md'
    )
    foreach ($relativePath in $trustedConfigurationPaths) {
        $candidate = Join-Path $ReviewDataRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $candidate) {
            Remove-Item -LiteralPath $candidate -Recurse -Force
        }
    }
}

function Save-ReviewDiff {
    $gitArgs = @('-C', $AnalysisWorkspace, 'diff', '--no-ext-diff', '--binary', $DiffRange) + (Get-PathSpecArgs)
    $diff = Invoke-GitCommand -Arguments $gitArgs
    Set-Content -LiteralPath (Join-Path $AgentWorkDir $ReviewDiffFileName) `
        -Value $diff `
        -Encoding UTF8
}

function Get-CopilotSecurityArguments {
    param([Parameter(Mandatory)][string] $WritablePath)

    $writable = ($WritablePath -replace '\\', '/')
    return @(
        '--available-tools', 'view', 'glob', 'rg', 'apply_patch',
        '--disallow-temp-dir',
        '--allow-tool', 'view',
        '--allow-tool', 'glob',
        '--allow-tool', 'rg',
        '--allow-tool', "write($writable)",
        '--deny-tool', 'shell',
        '--deny-tool', 'url',
        '--secret-env-vars', 'GH_TOKEN,GITHUB_TOKEN,COPILOT_GITHUB_TOKEN'
    )
}

function Get-ValidatedPrHeadCommit {
    param(
        [Parameter(Mandatory)][string] $RemoteRef,
        [Parameter(Mandatory)][string] $ExpectedHeadSha
    )

    if ($ExpectedHeadSha -notmatch '\A[a-fA-F0-9]{40}\z') {
        throw "Expected PR head must be a full 40-character commit SHA; received '$ExpectedHeadSha'."
    }

    $resolvedHead = @(
        Invoke-GitCommand -Arguments @(
            '-C',
            $TrustedWorkspace,
            'rev-parse',
            '--verify',
            "$RemoteRef^{commit}"
        )
    ) | Select-Object -First 1
    $resolvedHead = ([string]$resolvedHead).Trim()
    if ($resolvedHead -notmatch '\A[a-fA-F0-9]{40}\z') {
        throw "Fetched PR head '$RemoteRef' did not resolve to a full commit SHA."
    }
    if (-not $resolvedHead.Equals($ExpectedHeadSha, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Fetched PR head '$resolvedHead' does not match validated PR_HEAD_SHA '$ExpectedHeadSha'. The pull request changed after this review started."
    }

    return $resolvedHead.ToLowerInvariant()
}

function New-PrAnalysisWorktree {
    Write-Host "Fetching base branch origin/$BaseBranch"
    $null = Invoke-GitCommandAuthenticated -Arguments @('-C', $TrustedWorkspace, 'fetch', 'origin', $BaseBranch, '--no-tags')

    $prRef = "refs/pull/$PrNumber/head"
    $remoteRef = "refs/remotes/origin/pr/$PrNumber"
    Write-Host "Fetching PR head $prRef"
    $null = Invoke-GitCommandAuthenticated -Arguments @('-C', $TrustedWorkspace, 'fetch', 'origin', "+$prRef`:$remoteRef", '--no-tags')
    $validatedHead = Get-ValidatedPrHeadCommit -RemoteRef $remoteRef -ExpectedHeadSha $PrHeadSha

    $analysisParent = Split-Path -Parent $AnalysisWorkspace
    if (-not (Test-Path $analysisParent)) {
        New-Item -Path $analysisParent -ItemType Directory -Force | Out-Null
    }

    & git -C $TrustedWorkspace worktree remove --force $AnalysisWorkspace 2>$null | Out-Null
    if (Test-Path $AnalysisWorkspace) {
        Remove-Item -LiteralPath $AnalysisWorkspace -Recurse -Force
    }

    Write-Host "Checking out PR head into detached analysis worktree ($AnalysisWorkspace)"
    $null = Invoke-GitCommand -Arguments @('-C', $TrustedWorkspace, 'worktree', 'add', '--detach', '--force', $AnalysisWorkspace, $validatedHead)
}
