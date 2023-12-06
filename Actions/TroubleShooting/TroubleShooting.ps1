Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [string] $gitHubSecrets = ""
)

$errors = @()
$warnings = @()
$suggestions = @()

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

. (Join-Path -Path $PSScriptRoot -ChildPath "TroubleShoot.Secrets.ps1" -Resolve) -gitHubSecrets ($gitHubSecrets | ConvertFrom-Json)

if ($errors.Count -eq 0) { $errors = @("No errors found") }
if ($warnings.Count -eq 0) { $warnings = @("No warnings found") }
if ($suggestions.Count -eq 0) { $suggestions = @("No suggestions found") }

$summaryMD = (@("# Errors") + $errors + @("# Warnings") + $warnings + @("# Suggestions") + $suggestions) -join "`n`n"
Set-Content $ENV:GITHUB_STEP_SUMMARY -Value $summaryMD
