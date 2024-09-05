Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [string] $gitHubSecrets,
    [Parameter(HelpMessage = "Display the name (not the value) of secrets available to the repository", Mandatory = $true)]
    [bool] $displayNameOfSecrets
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$script:errors = @()
$script:warnings = @()
$script:suggestions = @()

function OutputWarning {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:warnings += "- $Message"
    Write-Host "- Warning: $Message"
}

function OutputError {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:errors += "- $Message"
    Write-Host "- Error: $Message"
}

function OutputSuggestion {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $script:suggestions += "- $Message"
    Write-Host "- Suggestion: $Message"
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

TestALGoRepository

. (Join-Path -Path $PSScriptRoot -ChildPath "Troubleshoot.Secrets.ps1" -Resolve) -gitHubSecrets ($gitHubSecrets | ConvertFrom-Json) -displayNameOfSecrets $displayNameOfSecrets

if ($script:errors.Count -eq 0) { $script:errors = @("No errors found") }
if ($script:warnings.Count -eq 0) { $script:warnings = @("No warnings found") }
if ($script:suggestions.Count -eq 0) { $script:suggestions = @("No suggestions found") }

$summaryMD = @"
# Troubleshooting
This workflow runs a number of tests to check if the repository is configured correctly. This workflow is work-in-progress and will be updated with more tests over time.

Please follow and/or include any recommendations here before [creating an issue on GitHub](https://github.com/microsoft/AL-Go/issues)`n`n
"@

$summaryMD += (@("## Errors") + $script:errors + @("## Warnings") + $script:warnings + @("## Suggestions") + $script:suggestions) -join "`n"
Set-Content $ENV:GITHUB_STEP_SUMMARY -Value $summaryMD
