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
    Runs the normal tests (testFolders) of an AL-Go project against the build container that the
    RunPipeline action created and kept alive. This runs as part of the build when the
    useSeparateTestAction setting is enabled; when it is not, RunPipeline runs the tests instead.
    Results are written to TestResults.xml in the project folder.

    Only normal tests (testFolders) are run here. BCPT and page scripting tests are run by the
    RunPipeline action.
.PARAMETER token
    The GitHub token running the action. It is exposed as the _token environment variable so
    downstream test override scripts (for example, BCApps test tolerance, which downloads the
    unstable-tests artifact) can authenticate against GitHub.
.PARAMETER project
    Project folder.
.PARAMETER installTestAppsJson
    A path to a JSON-formatted list of test apps (produced by previous jobs) to run tests in.
.EXAMPLE
    RunTests.ps1 -project 'MyProject'
#>

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path $PSScriptRoot 'RunTests.psm1' -Resolve) -DisableNameChecking -Force
DownloadAndImportBcContainerHelper

function Get-TestRunnerCredential {
    <#
    .SYNOPSIS
        Returns the credential used by the test runner to connect to the build container.
    .DESCRIPTION
        RunPipeline creates the container and keeps it alive when useSeparateTestAction is set.
        When RunPipeline surfaces the container credential (masked, as base64-encoded JSON in
        the containerCredential environment variable), it is used here so the test runner can
        connect to the same container. Otherwise a default credential is used.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The container credential is surfaced by RunPipeline as plain text')]
    param()
    if ($ENV:containerCredential) {
        $credentialJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ENV:containerCredential)) | ConvertFrom-Json
        $securePassword = ConvertTo-SecureString -String $credentialJson.password -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($credentialJson.username, $securePassword)
    }
    $securePassword = ConvertTo-SecureString -String ([GUID]::NewGuid().ToString()) -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential("admin", $securePassword)
}

if ($project -eq ".") { $project = "" }

$baseFolder = $ENV:GITHUB_WORKSPACE
$projectPath = Join-Path $baseFolder $project

Write-Host "Use settings"
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable

# Surface the token so RunTestsInBcContainer override scripts (e.g. BCApps test tolerance) can authenticate against GitHub.
$ENV:_token = $token

# Analyze the repository to determine the test folders (and other test related settings)
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting

# Resolve the container kept alive by RunPipeline (name is deterministic per project, also exported to the environment).
$containerName = $ENV:containerName
if (-not $containerName) {
    $containerName = GetContainerName($project)
}

# Credentials used to connect to the build container.
$credential = Get-TestRunnerCredential

# A RunTestsInBcContainer override script, if present, replaces the built-in BcContainerHelper test runner.
$overrideParams = Get-ScriptOverrides -ALGoFolderName (Join-Path $projectPath ".AL-Go") -OverrideScriptNames @("RunTestsInBcContainer")

Invoke-AlGoTestRun `
    -settings $settings `
    -projectPath $projectPath `
    -containerName $containerName `
    -credential $credential `
    -installTestAppsJson $installTestAppsJson `
    -runTestsOverride $overrideParams['RunTestsInBcContainer']
