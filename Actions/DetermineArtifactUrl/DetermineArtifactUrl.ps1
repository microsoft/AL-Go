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
