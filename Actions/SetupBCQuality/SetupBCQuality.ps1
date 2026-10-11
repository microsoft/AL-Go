<#
.SYNOPSIS
Installs and physically filters the BCQuality Copilot plugin.
#>
[CmdletBinding()]
param(
    [Parameter(HelpMessage = "GitHub owner/repository containing the BCQuality marketplace")]
    [string] $marketplace = 'microsoft/BCQuality',
    [Parameter(HelpMessage = "Immutable BCQuality marketplace tag, or a branch for prototype testing")]
    [string] $marketplaceRef = 'main',
    [Parameter(HelpMessage = "Expected version from the BCQuality marketplace entry")]
    [string] $expectedPluginVersion = '0.2.0',
    [Parameter(HelpMessage = "Comma-separated BCQuality layers to retain")]
    [string] $enabledLayers = 'microsoft',
    [Parameter(HelpMessage = "Comma-separated repo-relative skill paths to remove")]
    [string] $disabledSkills = '',
    [Parameter(HelpMessage = "Comma-separated knowledge globs to retain; empty retains all enabled-layer knowledge")]
    [string] $knowledgeAllow = '',
    [Parameter(HelpMessage = "Comma-separated knowledge globs to remove")]
    [string] $knowledgeDeny = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0

& (Join-Path $PSScriptRoot 'SetupBCQuality.Helper.ps1') @PSBoundParameters
