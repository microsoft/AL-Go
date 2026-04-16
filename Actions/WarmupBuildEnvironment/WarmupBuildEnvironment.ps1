Param(
    [Parameter(HelpMessage = "ArtifactUrl to use", Mandatory = $false)]
    [string] $artifact = ""
)

# Start background downloads for docker image and BC artifacts
# so they are cached by the time SetupBuildEnvironment runs.

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable

if ($settings.doNotPublishApps) {
    Write-Host "doNotPublishApps is set - skipping warmup"
    return
}

if (-not $isWindows) {
    Write-Host "Not running on Windows - skipping warmup (no container support)"
    return
}

# 1) Start docker pull as background process
$genericImageName = Get-BestGenericImageName
Write-Host "Starting background docker pull for $genericImageName"
Start-Process -FilePath "docker" -ArgumentList "pull","--quiet",$genericImageName -NoNewWindow

# 2) Start BC artifact download as background process
# Download-Artifacts caches to c:\bcartifacts.cache, which New-BcContainer reuses
if ($artifact) {
    Write-Host "Starting background BC artifact download for $($artifact.Split('?')[0])"
    $bcchModule = (Get-Module BcContainerHelper).Path
    $downloadScript = Join-Path $env:RUNNER_TEMP "warmup-download-artifacts.ps1"
    @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
Import-Module '$bcchModule' -DisableNameChecking
Download-Artifacts -artifactUrl '$artifact' -includePlatform
"@ | Set-Content -Path $downloadScript -Encoding UTF8

    Start-Process -FilePath "powershell" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$downloadScript -NoNewWindow
}

Write-Host "Background downloads started - they will complete while other steps run"
