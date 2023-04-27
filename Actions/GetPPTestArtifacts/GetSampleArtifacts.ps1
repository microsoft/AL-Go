Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

function Get-Artifacts {
    # Define the URL of the repository's latest release API endpoint
    $apiUrl = "https://api.github.com/repos/andersgMSFT/bcSampleAppsTest/releases/latest"

    # Set the GitHub API token if necessary
    $headers = @{ "Authorization" = $token }

    Write-Host "Getting artifacts from $apiUrl"
    # Call the API endpoint and parse the JSON response
    $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers
    $assets = $response.assets

    if ($assets.count -gt 1) {
        Write-Warning "More than one asset found. Only Downloading the first one."
    }

    if ($assets.count -eq 0) {
        Write-Error "No solutions found."
        throw "No solutions found."
    }

    $asset = $assets[0];
    $filePath = $asset.name
    write-host "Downloading: $filePath"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $filePath
    Add-Content -Path $env:GITHUB_ENV -Value "bcSampleAppFilePath=$filePath"

    $filename = $filePath.SubString(0, $filePath.Length - 4)
    Add-Content -Path $env:GITHUB_ENV -Value "bcSampleAppFile=$filename"

}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null

Write-Host "Get BC sample apps"

# IMPORTANT: No code that can fail should be outside the try/catch
try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0075' -parentTelemetryScopeJson $parentTelemetryScopeJson

    Get-Artifacts

    Write-Host "Arifacts downloaded"
}
catch {
    OutputError -message "Deploy action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
