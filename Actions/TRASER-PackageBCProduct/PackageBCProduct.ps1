# TRASER Product Packaging - extracted from TraserBCHelper Package-ALProduct

Param(
    [Parameter(Mandatory)][string]$ArtifactsFolder,
    [Parameter(Mandatory)][string]$Output,
    [string]$TargetBCVersion = '',
    [string]$TargetBCCountry = 'w1'
)

New-Item -ItemType Directory -Path $Output -Force | Out-Null
$appFiles = Get-ChildItem -Path $ArtifactsFolder -Filter "*.app" -Recurse
if ($appFiles.Count -eq 0) { Write-Error "No .app files found"; return }

$primaryApp = Get-AppJsonFromAppFile -appFile $appFiles[0].FullName
$publisher = $primaryApp.publisher; $name = $primaryApp.name; $version = $primaryApp.version

# SaaS package
$saasDir = Join-Path $Output "saas-temp"
New-Item -ItemType Directory -Path $saasDir -Force | Out-Null
Copy-Item "$ArtifactsFolder\*.app" -Destination $saasDir -Recurse
$saasZip = Join-Path $Output "${publisher}_${name}_${version}_SAAS.zip"
Compress-Archive -Path "$saasDir\*" -DestinationPath $saasZip -Force
Remove-Item $saasDir -Recurse -Force
Write-Host "Created: $(Split-Path $saasZip -Leaf)"
Add-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Value "saas-package=$saasZip"

# Runtime package
if ($TargetBCVersion) {
    $rtDir = Join-Path $Output "runtime-temp"
    New-Item -ItemType Directory -Path $rtDir -Force | Out-Null
    Copy-Item "$ArtifactsFolder\*.app" -Destination $rtDir -Recurse
    $rtZip = Join-Path $Output "${publisher}_${name}_${version}_RUNTIME-${TargetBCVersion}-${TargetBCCountry}.zip"
    Compress-Archive -Path "$rtDir\*" -DestinationPath $rtZip -Force
    Remove-Item $rtDir -Recurse -Force
    Write-Host "Created: $(Split-Path $rtZip -Leaf)"
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Value "runtime-package=$rtZip"
}
