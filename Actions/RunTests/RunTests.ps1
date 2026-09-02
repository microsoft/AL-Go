Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to run tests in", Mandatory = $false)]
    [string] $installTestAppsJson = ''
)

<#
.SYNOPSIS
    Runs the normal tests (testFolders) for an AL-Go project against the build container
    created and kept alive by the RunPipeline action.
.DESCRIPTION
    Runs normal tests in eligible separate-test builds. Test results remain in the project folder
    for AnalyzeTests and are copied to .buildartifacts when produced. The action also refreshes the
    project container event log for failure diagnostics. BCPT and page scripting tests remain in
    RunPipeline.
.PARAMETER token
    The GitHub token running the action. It is exposed to test override scripts as _token.
.PARAMETER project
    Project folder.
.PARAMETER installTestAppsJson
    A path to a JSON-formatted list of test apps (produced by previous jobs) to run tests in.
.EXAMPLE
    RunTests.ps1 -project 'MyProject'
#>

# Make the token available to RunTestsInBcContainer overrides.
$ENV:_token = $token

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path $PSScriptRoot 'RunTests.psm1' -Resolve) -DisableNameChecking -Force

function Get-TestRunnerCredential {
    <#
    .SYNOPSIS
        Returns the credential used by the test runner to connect to the build container.
    .DESCRIPTION
        Uses the credential supplied by RunPipeline and fails when that pipeline output is unavailable.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The container credential is surfaced by RunPipeline as plain text')]
    param()

    if ([string]::IsNullOrWhiteSpace($ENV:containerCredential)) {
        throw "RunPipeline-to-RunTests wiring error: the kept container credential was not provided."
    }

    try {
        $credentialJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ENV:containerCredential)) |
            ConvertFrom-Json |
            ConvertTo-HashTable -recurse
        if ([string]::IsNullOrWhiteSpace("$($credentialJson.username)") -or [string]::IsNullOrWhiteSpace("$($credentialJson.password)")) {
            throw "The credential does not contain a username and password."
        }
        $securePassword = ConvertTo-SecureString -String $credentialJson.password -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($credentialJson.username, $securePassword)
    }
    catch {
        throw "RunPipeline-to-RunTests wiring error: the kept container credential was not provided in the expected format."
    }
}

function Get-TestRunnerContainerName {
    <#
    .SYNOPSIS
        Returns the kept container name supplied by RunPipeline.
    #>
    param()

    if ([string]::IsNullOrWhiteSpace($ENV:containerName)) {
        throw "RunPipeline-to-RunTests wiring error: the kept container name was not provided."
    }

    return $ENV:containerName
}

if ($project -eq ".") { $project = "" }

$baseFolder = $ENV:GITHUB_WORKSPACE
$projectPath = Join-Path $baseFolder $project
$containerName = Get-TestRunnerContainerName
$credential = Get-TestRunnerCredential

DownloadAndImportBcContainerHelper
Write-Host "Use settings"
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse

$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting

# A RunTestsInBcContainer override script, if present, replaces the built-in AlTool test runner.
$overrideParams = Get-ScriptOverrides -ALGoFolderName (Join-Path $projectPath ".AL-Go") -OverrideScriptNames @("RunTestsInBcContainer")

Invoke-AlGoTestRun `
    -settings $settings `
    -projectPath $projectPath `
    -containerName $containerName `
    -credential $credential `
    -installTestAppsJson $installTestAppsJson `
    -runTestsOverride $overrideParams['RunTestsInBcContainer']
