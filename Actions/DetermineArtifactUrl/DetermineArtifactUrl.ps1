Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "."
)

#region Action: Setup
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper
#endregion

#region Action: Determine artifacts to use based on cicdAuthContext or settings
$artifactUrl = $null
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
if ($env:Secrets) {
    $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable
    if ($secrets.ContainsKey('cicdAuthContext') -and $settings.cicdEnvironmentName) {
        $cicdAuthContext = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets.cicdAuthContext))
        $authContextHT = $cicdAuthContext | ConvertFrom-Json | ConvertTo-HashTable
        $environmentName = $settings.cicdEnvironmentName
        if ($environmentName -notlike 'https://*') {
            $authContext = New-BcAuthContext @authContextHT
            $bcEnvironment = Get-BcEnvironments -bcAuthContext $authContext | Where-Object { $_.name -eq $environmentName -and $_.type -eq "Sandbox" }
            if (-not $bcEnvironment) {
                throw "Business Central online environment '$environmentName' not found"
            }
            $settings.useCompilerFolder = $true
            $bcBaseApp = Get-BcPublishedApps -bcAuthContext $authContext -environment $environmentName | Where-Object { $_.Name -eq "Base Application" -and $_.state -eq "installed" }
            if (-not $bcBaseApp) {
                throw "Base Application not found in environment '$environmentName'"
            }
            $artifactUrl = Get-BCArtifactUrl -type Sandbox -country $bcEnvironment.countryCode -version $bcBaseApp.Version -select Closest
        }
    }
}
if (!$artifactUrl) {
    $settings = AnalyzeRepo -settings $settings -project $project -doNotCheckArtifactSetting -doNotIssueWarnings
    $artifactUrl = DetermineArtifactUrl -projectSettings $settings
}
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
