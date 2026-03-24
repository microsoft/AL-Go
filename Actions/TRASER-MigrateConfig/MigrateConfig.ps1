# TRASER config.json to AL-Go settings.json Migration

Param(
    [string]$ConfigJsonPath = "./config.json",
    [string]$OutputPath = "./.AL-Go/settings.json",
    [ValidateSet("master", "release")][string]$MainBranchDependencyStrategy = "master"
)

if (-not (Test-Path $ConfigJsonPath)) { Write-Error "config.json not found at $ConfigJsonPath"; return }
$config = Get-Content -Encoding UTF8 $ConfigJsonPath | ConvertFrom-Json

$settings = [ordered]@{
    '$schema' = "https://raw.githubusercontent.com/microsoft/AL-Go-Actions/v8.3/.Modules/settings.schema.json"
    country = "de"; appFolders = @(); testFolders = @(); bcptTestFolders = @()
    gitHubRunner = "[ self-hosted, windows ]"; gitHubRunnerShell = "powershell"
}

if ($config.PSObject.Properties.Name -contains 'apppath' -and $config.apppath) { $settings.appFolders = @($config.apppath) }
if ($config.PSObject.Properties.Name -contains 'testpath' -and $config.testpath) { $settings.testFolders = @($config.testpath) }
if ($config.PSObject.Properties.Name -contains 'bcversion' -and $config.bcversion.PSObject.Properties.Name -contains 'country') { $settings.country = $config.bcversion.country }

$settings.CICDPushBranches = @("main", "staging", "release/*", "feature/*")
$settings.CICDPullRequestTargetBranches = @("main", "staging", "release/*")

$runtimeFeed = "https://pkgs.dev.azure.com/TRASERSoftwareGmbH/57865e76-6f0b-4dd0-967d-d899bfd89907/_packaging/bc-runtime/nuget/v3/index.json"
$mainFeed = if ($MainBranchDependencyStrategy -eq "release") { $runtimeFeed -replace "bc-runtime", "bc-release" } else { $runtimeFeed -replace "bc-runtime", "bc-master" }
$stagingFeed = $runtimeFeed -replace "bc-runtime", "bc-staging"
$releaseFeed = $runtimeFeed -replace "bc-runtime", "bc-release"

$settings.trustedNuGetFeeds = @([ordered]@{ url = $runtimeFeed; authTokenSecret = "NUGET_TOKEN" })
$settings.ConditionalSettings = @(
    [ordered]@{ branches = @("staging"); settings = [ordered]@{ versioningStrategy = 0; trustedNuGetFeeds = @([ordered]@{ url = $stagingFeed; authTokenSecret = "NUGET_TOKEN" }, [ordered]@{ url = $runtimeFeed; authTokenSecret = "NUGET_TOKEN" }) } }
    [ordered]@{ branches = @("main"); settings = [ordered]@{ trustedNuGetFeeds = @([ordered]@{ url = $mainFeed; authTokenSecret = "NUGET_TOKEN" }, [ordered]@{ url = $runtimeFeed; authTokenSecret = "NUGET_TOKEN" }) } }
    [ordered]@{ branches = @("release/*"); settings = [ordered]@{ trustedNuGetFeeds = @([ordered]@{ url = $releaseFeed; authTokenSecret = "NUGET_TOKEN" }, [ordered]@{ url = $runtimeFeed; authTokenSecret = "NUGET_TOKEN" }) } }
)

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$settings | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $OutputPath
Write-Host "Generated AL-Go settings at $OutputPath (strategy: $MainBranchDependencyStrategy)"
