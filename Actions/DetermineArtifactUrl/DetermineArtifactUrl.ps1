Param(
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

$telemetryScope = $null

try {
    #region Action: Setup
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    DownloadAndImportBcContainerHelper
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking
    #endregion

    #region Action: Determine artifacts to use
    $telemetryScope = CreateScope -eventId 'DO0084' -parentTelemetryScopeJson $parentTelemetryScopeJson
    $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
    $insiderSasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.insiderSasToken))
    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
    $settings = AnalyzeRepo -settings $settings -project $project -doNotCheckArtifactSetting -doNotIssueWarnings
    $artifactUrl = DetermineArtifactUrl -projectSettings $settings -insiderSasToken $insiderSasToken
    $artifactCacheKey = ''
    if ($settings.useCompilerFolder) {
        $artifactCacheKey = $artifactUrl.Split('?')[0]
    }
    #endregion

    #region Action: Output
    # Set output variables
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "artifact=$artifactUrl"
    Write-Host "artifact=$artifactUrl"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "artifactCacheKey=$artifactCacheKey"
    Write-Host "artifactCacheKey=$artifactCacheKey"
    #endregion

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
