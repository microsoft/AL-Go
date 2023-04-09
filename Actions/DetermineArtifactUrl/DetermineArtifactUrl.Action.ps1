Param(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    [string] $baseFolder,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"artifact":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":"xxx"}',
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    #region Action: Setup
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $bcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking
    #endregion
    
    #region Action: Determine projects to build
    $telemetryScope = CreateScope -eventId 'DO0084' -parentTelemetryScopeJson $parentTelemetryScopeJson
    $insiderSasToken = ConvertFrom-Json -InputObject $secretsJson | Select-Object -ExpandProperty insiderSasToken
    $projectSettings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $artifactUrl = Determine-ArtifactUrl -projectSettings $projectSettings -insiderSasToken $insiderSasToken
    $projectSettings.artifact = $artifactUrl
    #endregion

    #region Action: Output
    # Set output variables
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ArtifactUrl=$artifactUrl"
    Write-Host "ArtifactUrl=$artifactUrl"
    $outSettingsJson = $projectSettings | ConvertTo-Json -Depth 99 -Compress
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"
    Write-Host "SettingsJson=$outSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "artifact=$artifactUrl"
    Write-Host "Artifact=$artifactUrl"
    #endregion

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "DetermineArtifactUrl action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
    
