Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format (base64 encoded)", Mandatory = $false)]
    [string] $settingsJson = '{"artifact":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"insiderSasToken":""}'
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
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

    $useBase64 = $true
    try {
        $projectSettings = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($settingsJson)) | ConvertFrom-Json | ConvertTo-HashTable
    }
    catch {
        # Older versions of the action did not base64 encode the settings
        # In order to support in-place upgrade of the action in preview we need to support non-base64 encoded settings as well
        # This action will return the settings in non-base64 encoded format if the settings are not base64 encoded
        $projectSettings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
        $useBase64 = $false
    }
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
    Write-Host "OUTPUTS:"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ArtifactUrl=$artifactUrl"
    Write-Host "- ArtifactUrl=$artifactUrl"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ArtifactCacheKey=$artifactCacheKey"
    Write-Host "- ArtifactCacheKey=$artifactCacheKey"
    $outSettingsJson = $projectSettings | ConvertTo-Json -Depth 99 -Compress
    Write-Host "- SettingsJson=$outSettingsJson"
    if ($useBase64) {
        $outSettingsJson = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($outSettingsJson))
        Write-Host "::add-mask::$outSettingsJson"
    }
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "SettingsJson=$outSettingsJson"
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
    
