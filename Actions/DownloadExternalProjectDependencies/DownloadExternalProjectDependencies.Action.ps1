Param(
    [Parameter(HelpMessage = "A path to a JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
    .SYNOPSIS
    Downloads an app file from a URL to a specified download path.
    .DESCRIPTION
    Downloads an app file from a URL to a specified download path.
    It handles URL decoding and sanitizes the file name.
    .PARAMETER Url
    The URL of the app file to download.
    .PARAMETER DownloadPath
    The path where the app file should be downloaded.
    .OUTPUTS
    The path to the downloaded app file.
#>
function Get-AppFileFromUrl {
    Param(
        [string] $Url,
        [string] $DownloadPath
    )
    # Get the file name from the URL
    $urlWithoutQuery = $Url.Split('?')[0].TrimEnd('/')
    $rawFileName = [System.IO.Path]::GetFileName($urlWithoutQuery)
    $decodedFileName = [Uri]::UnescapeDataString($rawFileName)
    $decodedFileName = [System.IO.Path]::GetFileName($decodedFileName)

    # Sanitize file name by removing invalid characters
    $sanitizedFileName = $decodedFileName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $sanitizedFileName = $sanitizedFileName.Trim()

    # Get the final app file path
    $appFile = Join-Path $DownloadPath $sanitizedFileName
    Invoke-WebRequest -Method GET -UseBasicParsing -Uri $Url -OutFile $appFile -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
    return $appFile
}

# Get settings and secrets from environment variables
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
# ENV:Secrets is not set when running Pull_Request trigger
if ($env:Secrets) {
    $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
}
else {
    $secrets = @{}
}

# Initialize install apps and test apps from settings and additional JSON files
$install = @{
    "Apps" = $settings.installApps
    "TestApps" = $settings.installTestApps
}

if ($installAppsJson -and (Test-Path $installAppsJson)) {
    try {
        $install.Apps += @(Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse JSON file at path '$installAppsJson'. Error: $($_.Exception.Message)"
    }
}

if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
    try {
        $install.TestApps += @(Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
    }
}

# Replace secret names in install.apps and install.testApps and download files from URLs
$tempDependenciesLocation = NewTemporaryFolder
foreach($list in @('Apps','TestApps')) {
    $install."$list" = @($install."$list" | ForEach-Object {
        $appFile = $_

        # If the app file is not a URL, return it as is
        if ($appFile -notlike 'http*://*') {
            return $appFile
        }

        # Else, check for secrets in the URL and replace them
        $appFileUrl = $appFile
        $pattern = '.*(\$\{\{\s*([^}]+?)\s*\}\}).*'
        if ($appFile -match $pattern) {
            $appFileUrl = $appFileUrl.Replace($matches[1],[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$($matches[2])")))
        }

        # Download the app file to a temporary location
        try {
            $appFile = Get-AppFileFromUrl -Url $appFileUrl -DownloadPath $tempDependenciesLocation
        } catch {
            throw "Setting: install$($list) contains an inaccessible URL: $($_). Error was: $($_.Exception.Message)"
        }

        return $appFile
    })
}

OutputMessageAndArray -message "External dependencies (Apps)" -arrayOfStrings $install.Apps
OutputMessageAndArray -message "External dependencies (Test Apps)" -arrayOfStrings $install.TestApps

# Update installAppsJson and installTestAppsJson files with downloaded app file paths
if ($installAppsJson -and (Test-Path $installAppsJson)) {
    ConvertTo-Json $install.Apps -Depth 99 -Compress | Set-Content -Path $installAppsJson -Encoding UTF8
}
if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
    ConvertTo-Json $install.TestApps -Depth 99 -Compress | Set-Content -Path $installTestAppsJson -Encoding UTF8
}