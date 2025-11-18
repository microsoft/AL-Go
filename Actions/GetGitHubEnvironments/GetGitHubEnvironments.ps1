. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$headers = GetHeaders -token $env:GITHUB_TOKEN
$url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"

OutputDebug "Url: $url"

try {
    Write-Host "Requesting environments from GitHub"
    $ghEnvironments = @(((InvokeWebRequest -Headers $headers -Uri $url).Content | ConvertFrom-Json).environments)
}
catch {
    $ghEnvironments = @()
    Write-Host "Failed to get environments from GitHub API - Environments are not supported in this repository"
}

Write-Host "Found $($ghEnvironments.Count) environment(s) in GitHub repository:"
if ($ghEnvironments.Count -gt 0) {
    $ghEnvironments | ForEach-Object {
        Write-Host "- $($_.name)"
    }
} else {
    Write-Host "- None"
}
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "GitHubEnvironments=$($ghEnvironments | ConvertTo-Json -Depth 99 -Compress)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "GitHubEnvironments=$($ghEnvironments | ConvertTo-Json -Depth 99 -Compress)"
