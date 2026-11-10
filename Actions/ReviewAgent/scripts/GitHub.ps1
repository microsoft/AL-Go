# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------
function Invoke-GitHubApi {
    param(
        [string] $Method,
        [string] $Endpoint,
        [hashtable] $Query,
        [object]  $Body
    )

    $url = "$BaseUrl$Endpoint"
    if ($Query) {
        $qs = ($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&'
        $url = "${url}?$qs"
    }

    $headers = @{
        Accept        = 'application/vnd.github+json'
        Authorization = "Bearer $GithubToken"
        'User-Agent'  = 'bcapps-copilot-pr-reviewer'
    }

    $params = @{
        Uri     = $url
        Method  = $Method
        Headers = $headers
    }

    if ($Body) {
        $params.Body        = ($Body | ConvertTo-Json -Depth 10 -Compress)
        $params.ContentType = 'application/json'
    }

    return Invoke-RestMethod @params
}

function Get-AllPages {
    param([string] $Endpoint)

    $all  = [System.Collections.Generic.List[object]]::new()
    $page = 1
    do {
        $result = Invoke-GitHubApi -Method GET -Endpoint $Endpoint -Query @{ per_page = 100; page = $page }
        if (-not $result) { break }
        $all.AddRange([object[]]$result)
        $page++
    } while ($result.Count -eq 100)

    return $all.ToArray()
}

function Get-PrFiles        { return Get-AllPages "/pulls/$PrNumber/files" }
function Get-ReviewComments { return Get-AllPages "/pulls/$PrNumber/comments" }
function Get-IssueComments  { return Get-AllPages "/issues/$PrNumber/comments" }

function New-ReviewComment {
    param(
        [string] $Body, [string] $Path, [int] $Line, [string] $Side,
        [int] $StartLine = 0, [string] $StartSide = ''
    )

    if (-not $Line -or -not $Side) {
        throw 'Inline review comments require both line and side.'
    }

    $payload = @{ body = $Body; commit_id = $PrHeadSha; path = $Path; line = $Line; side = $Side }
    # Multi-line comment: GitHub anchors the range over [start_line, line] so a
    # ```suggestion``` block replaces every spanned line in place (a single-line
    # comment would otherwise replace just $Line, duplicating context).
    if ($StartLine -gt 0 -and $StartLine -lt $Line) {
        $payload.start_line = $StartLine
        $payload.start_side = if ($StartSide) { $StartSide } else { $Side }
    }
    Invoke-GitHubApi -Method POST -Endpoint "/pulls/$PrNumber/comments" -Body $payload
}

function New-IssueComment {
    param([string] $Body)
    Invoke-GitHubApi -Method POST -Endpoint "/issues/$PrNumber/comments" -Body @{ body = $Body }
}

function Update-IssueComment {
    param([long] $CommentId, [string] $Body)
    Invoke-GitHubApi -Method PATCH -Endpoint "/issues/comments/$CommentId" -Body @{ body = $Body }
}

function Test-GitHubEnterpriseHost {
    param([string] $ServerUrl)
    $normalized = (($ServerUrl ?? '') + '').Trim().TrimEnd('/')
    return $normalized -ne '' -and $normalized -ne 'https://github.com'
}

function New-CopilotChildEnvironment {
    param(
        [string] $ReviewSource,
        [string] $CopilotToken,
        [string] $CopilotGithubToken,
        [string] $CiValue,
        [string] $GitHubServerUrl = 'https://github.com'
    )

    $allowedKeys = @('PATH','PATHEXT','HOME','USERPROFILE','TMP','TEMP','TMPDIR','APPDATA','LOCALAPPDATA',
                     'SystemRoot','ComSpec','CI','TERM','LANG','LC_ALL','npm_config_prefix','NPM_CONFIG_PREFIX')
    $cleanEnv = @{}
    foreach ($key in $allowedKeys) {
        $val = [System.Environment]::GetEnvironmentVariable($key)
        if ($val) { $cleanEnv[$key] = $val }
    }

    if ($ReviewSource -eq 'local') {
        if (-not [string]::IsNullOrWhiteSpace($CiValue) -and $CopilotGithubToken) {
            $cleanEnv['COPILOT_GITHUB_TOKEN'] = $CopilotGithubToken
        }
    }
    elseif ($CopilotToken) {
        # Use the CLI-specific authentication variable instead of exposing a
        # general-purpose gh credential to the reviewer process.
        $cleanEnv['COPILOT_GITHUB_TOKEN'] = $CopilotToken
    }

    # Copilot CLI authenticates against github.com unless told otherwise. On a
    # GitHub Enterprise host it needs the host to validate the forwarded token.
    if (Test-GitHubEnterpriseHost -ServerUrl $GitHubServerUrl) {
        $cleanEnv['COPILOT_GH_HOST'] = $GitHubServerUrl
    }

    $cleanEnv['CI'] = 'true'
    $cleanEnv['GIT_PAGER'] = 'cat'
    $cleanEnv['PAGER'] = 'cat'
    $cleanEnv['GIT_TERMINAL_PROMPT'] = '0'
    return $cleanEnv
}
