<#
.SYNOPSIS
Runs the Copilot pull request review engine.
#>
param()

$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Invoke-CopilotPRReview.psm1') -Force -DisableNameChecking
Invoke-CopilotPRReview
