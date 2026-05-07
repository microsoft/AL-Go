param (
    [string]$Path,
    [string[]]$ExcludeRule,
    [switch]$Recurse,
    [string]$Output
)

$analyzerModule = Get-Module -ListAvailable -Name PSScriptAnalyzer
if ($null -eq $analyzerModule) {
    Install-Module -Name PSScriptAnalyzer -Force
}

$sarifModule = Get-Module -ListAvailable -Name ConvertToSARIF
if ($null -eq $sarifModule) {
    Install-Module -Name ConvertToSARIF -Force
}
Import-Module -Name ConvertToSARIF -Force

$htPSA = [ordered]@{ Path = $Path }
if ($ExcludeRule) {
    Write-Host "Excluding rules: $ExcludeRule"
    $htPSA.add('ExcludeRule', $ExcludeRule)
}
if ($Recurse) {
    Write-Host "Recurse: $Recurse"
    $htPSA.add('Recurse', $true)
}
$htCTS = [ordered]@{ FilePath = $Output }

$maxRetries = 3
$retryCount = 0
$success = $false

# TypeNotFound records from the TestRunner module are expected because those files
# reference BC client types (via 'using namespace Microsoft.Dynamics.Framework.UI.Client')
# that are only available at runtime inside a BC container, not during static analysis.
# PSAvoidGlobalVars is suppressed for the TestRunner module because the test runner uses
# global variables for cross-module configuration sharing (e.g. $global:DefaultTestPage,
# $global:TestRunnerIsolationCodeunit). Refactoring to eliminate globals would require
# restructuring the module architecture.
# PSUseApprovedVerbs is suppressed for the TestRunner module because it exposes legacy
# Business Central function names that cannot be renamed without breaking the API.
# Authentication-related rules (PSAvoidUsingPlainTextForPassword, PSUsePSCredentialType,
# PSAvoidUsingAllowUnencryptedAuthentication) are suppressed for the TestRunner module
# because it uses BC client services credential patterns that don't follow standard
# PowerShell credential conventions.
$testRunnerPath = '.Modules' + [System.IO.Path]::DirectorySeparatorChar + 'TestRunner' + [System.IO.Path]::DirectorySeparatorChar

Write-Output "Modules installed, now running tests."
while (-not $success -and $retryCount -lt $maxRetries) {
    Try {
        Invoke-ScriptAnalyzer @htPSA -Verbose |
            Where-Object {
                -not ($_.ScriptPath.Contains($testRunnerPath) -and (
                    $_.RuleName -eq 'TypeNotFound' -or
                    $_.RuleName -eq 'PSAvoidGlobalVars' -or
                    $_.RuleName -eq 'PSUseApprovedVerbs' -or
                    $_.RuleName -eq 'PSAvoidUsingPlainTextForPassword' -or
                    $_.RuleName -eq 'PSUsePSCredentialType' -or
                    $_.RuleName -eq 'PSAvoidUsingAllowUnencryptedAuthentication'
                ))
            } |
            ConvertTo-SARIF @htCTS
        $success = $true
    } Catch {
        Write-Host "::Error:: $_"
        $retryCount++
        Write-Output "Retrying... ($retryCount/$maxRetries)"
    }
}

if (-not $success) {
    Write-Host "::Error:: Failed after $maxRetries attempts."
    exit 1
}
