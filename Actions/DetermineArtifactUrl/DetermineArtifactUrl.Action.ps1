Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"artifact":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":""}'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    #region Action: Setup
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking
    #endregion
    
    #region Action: Determine artifacts to use
    $telemetryScope = CreateScope -eventId 'DO0084' -parentTelemetryScopeJson $parentTelemetryScopeJson
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $insiderSasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.insiderSasToken))
    $projectSettings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $projectSettings = AnalyzeRepo -settings $projectSettings -project $project -doNotCheckArtifactSetting -doNotIssueWarnings
    $artifactUrl = Determine-ArtifactUrl -projectSettings $projectSettings -insiderSasToken $insiderSasToken
    $artifactCacheKey = ''
    $projectSettings.artifact = $artifactUrl
    if ($projectSettings.useCompilerFolder) {
        $artifactCacheKey = $artifactUrl.Split('?')[0]
    }
    #endregion

    #region Action: Output
    # Set output variables
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ArtifactUrl=$artifactUrl"
    Write-Host "ArtifactUrl=$artifactUrl"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ArtifactCacheKey=$artifactCacheKey"
    Write-Host "ArtifactCacheKey=$artifactCacheKey"
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
    
