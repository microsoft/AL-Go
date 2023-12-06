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

function OutputWarning {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    AddToSummary -type Warning -Message $Message
}

function OutputError {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    AddToSummary -type Error -Message $Message
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

try {
    TestALGoRepository
}
catch {
    OutputError -Message $_.Exception.Message
}

. (Join-Path -Path $PSScriptRoot -ChildPath "TroubleShoot.Secrets.ps1" -Resolve) -gitHubSecrets ($gitHubSecrets | ConvertFrom-Json)

if ($global:errors.Count -eq 0) { $global:errors = @("No errors found") }
if ($global:warnings.Count -eq 0) { $global:warnings = @("No warnings found") }
if ($global:suggestions.Count -eq 0) { $global:suggestions = @("No suggestions found") }

$summaryMD = @"
# Troubleshooting
This workflow runs a number of tests to check if the repository is configured correctly. This workflow is work-in-progress and will be updated with more tests over time.

Please follow and/or include any recommendations here before [creating an issue on GitHub](https://github.com/microsoft/AL-Go/issues)`n`n
"@

$summaryMD += (@("## Errors") + $global:errors + @("## Warnings") + $global:warnings + @("## Suggestions") + $global:suggestions) -join "`n"
Set-Content $ENV:GITHUB_STEP_SUMMARY -Value $summaryMD
