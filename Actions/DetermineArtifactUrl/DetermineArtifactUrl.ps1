Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

#region Action: Setup
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper
#endregion

#region Action: Determine artifacts to use
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -project $project -doNotCheckArtifactSetting -doNotIssueWarnings
$artifactUrl = DetermineArtifactUrl -projectSettings $settings
$artifactCacheKey = ''
if ($settings.useCompilerFolder -and $settings.symbolsSource -ne 'nuGet') {
    # An empty cache key switches off the Cache Business Central Artifacts steps in the
    # workflow. When symbols come from NuGet the artifact is never downloaded, so caching
    # it would only cost a ~1 GB restore and a cache entry nothing reads.
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
