Param(
    [Parameter(HelpMessage = "The GitHub token to use to fetch the changed files", Mandatory = $false)]
    [string] $token
)

function Get-ModifiedFiles($token) {
    if(!$env:GITHUB_EVENT_PATH) {
        Write-Host "GITHUB_EVENT_PATH not set, returning empty list of changed files"
        return @()
    }
    
    $ghEvent = Get-Content $env:GITHUB_EVENT_PATH -Encoding UTF8 | ConvertFrom-Json

    if(!$ghEvent) {
        Write-Host "Could not read GITHUB_EVENT_PATH, returning empty list of changed files"
        return @()
    }
    
    $url = "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)/compare/$($ghEvent.pull_request.base.sha)...$($ghEvent.pull_request.head.sha)"
    
    $headers = @{             
        "Authorization" = "token $token"
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }
    $response = InvokeWebRequest -Headers $headers -Uri $url | ConvertFrom-Json
    $filesChanged = @($response.files | ForEach-Object { $_.filename })

    return $filesChanged
}

$modifiedFiles = Get-ModifiedFiles -token $token
$modifiedFilesJson = ConvertTo-Json $modifiedFiles -Depth 99 -Compress
    
# Set output variables
Add-Content -Path $env:GITHUB_OUTPUT -Value "modifiedFiles=$modifiedFilesJson"

Write-Host "modifiedFiles=$modifiedFilesJson"