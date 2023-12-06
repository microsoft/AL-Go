Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [string] $gitHubSecrets = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$global:errors = @()
$global:warnings = @()
$global:suggestions = @()

function AddToSummary {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Error', 'Warning', 'Suggestion')]
        [string] $type
    )

    switch($type) {
        'Error' {
            $global:errors += "- $Message"
            Write-Host "- $Message"
        }
        'Warning' {
            $global:warnings += "- $Message"
            Write-Host "- $Message"
        }
        'Suggestion' {
            $global:suggestions += "- $Message"
            Write-Host "- $Message"
        }
    }
}

. (Join-Path -Path $PSScriptRoot -ChildPath "TroubleShoot.Secrets.ps1" -Resolve) -gitHubSecrets ($gitHubSecrets | ConvertFrom-Json)
. (Join-Path -Path $PSScriptRoot -ChildPath "TroubleShoot.Settings.ps1" -Resolve)

if ($global:errors.Count -eq 0) { $global:errors = @("No errors found") }
if ($global:warnings.Count -eq 0) { $global:warnings = @("No warnings found") }
if ($global:suggestions.Count -eq 0) { $global:suggestions = @("No suggestions found") }

$summaryMD = @"
# Troubleshooting
This workflow runs a number of tests to check if the repository is configured correctly. This workflow is work-in-progress and will be updated with more tests over time.

> [!NOTE]
> Please follow recommendations given here before [creating an issue](https://github.com/microsoft/AL-Go/issues)`n`n
"@

$summaryMD += (@("## Errors") + $global:errors + @("## Warnings") + $global:warnings + @("## Suggestions") + $global:suggestions) -join "`n"
Set-Content $ENV:GITHUB_STEP_SUMMARY -Value $summaryMD
