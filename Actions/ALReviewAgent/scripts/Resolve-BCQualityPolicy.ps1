<#
.SYNOPSIS
Resolves BCQuality policy inputs into SetupBCQuality action values.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$cfg = & (Join-Path $PSScriptRoot 'Get-BCQualityConfig.ps1')
$repoUri = [Uri] $cfg.bcquality.repo
if ($repoUri.Scheme -ne 'https' -or $repoUri.Host -ne 'github.com') {
    throw "BCQuality marketplace must use an https://github.com URL; received '$($cfg.bcquality.repo)'."
}
$marketplace = $repoUri.AbsolutePath.Trim('/')
if ($marketplace -notmatch '^[^/]+/[^/]+$') {
    throw "BCQuality marketplace URL must identify one owner/repository; received '$($cfg.bcquality.repo)'."
}
$pluginVersion = [string] $cfg.bcquality['plugin-version']
if (-not $pluginVersion) {
    throw 'bcquality.plugin-version is required for plugin identity validation.'
}

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "marketplace=$marketplace"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "marketplaceRef=$($cfg.bcquality.ref)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "pluginVersion=$pluginVersion"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "enabledLayers=$(@($cfg['enabled-layers']) -join ',')"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "disabledSkills=$(@($cfg['disabled-skills']) -join ',')"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "knowledgeAllow=$(@($cfg.knowledge.allow) -join ',')"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "knowledgeDeny=$(@($cfg.knowledge.deny) -join ',')"
