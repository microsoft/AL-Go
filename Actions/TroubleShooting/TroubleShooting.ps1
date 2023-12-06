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
            Write-Host "Error: $Message"
        }
        'Warning' {
            $global:warnings += "- $Message"
            Write-Host "Warning: $Message"
        }
        'Suggestion' {
            $global:suggestions += "- $Message"
            Write-Host "Suggestion: $Message"
        }
    }
}

. (Join-Path -Path $PSScriptRoot -ChildPath "TroubleShoot.Secrets.ps1" -Resolve) -gitHubSecrets ($gitHubSecrets | ConvertFrom-Json)

if ($global:errors.Count -eq 0) { $global:errors = @("No errors found") }
if ($global:warnings.Count -eq 0) { $global:warnings = @("No warnings found") }
if ($global:suggestions.Count -eq 0) { $global:suggestions = @("No suggestions found") }

$summaryMD = (@("# Errors") + $global:errors + @("# Warnings") + $global:warnings + @("# Suggestions") + $global:suggestions) -join "`n`n"
Set-Content $ENV:GITHUB_STEP_SUMMARY -Value $summaryMD
