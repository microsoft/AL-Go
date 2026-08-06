Param(
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'token', Justification = 'Exposed as $env:_token via action.yaml so downstream test override scripts (e.g. BCApps test tolerance artifact download) can authenticate.')]
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
    This action is the second half of the "split" between building/publishing apps and running
    tests. It only does anything when the useSeparateTestAction setting is enabled. In that
    case, RunPipeline compiles, publishes and installs the apps, skips the normal tests and
    keeps the build container alive. This action then runs the normal tests against that same
    container and writes the results to TestResults.xml in the project folder (the location the
    AnalyzeTests action reads from).

    Only normal tests (testFolders) are handled here. BCPT and page scripting tests continue
    to be executed by the RunPipeline action.
.PARAMETER token
    The GitHub token running the action. It is exposed as the _token environment variable by
    action.yaml so downstream test override scripts (for example, BCApps test tolerance, which
    downloads the unstable-tests artifact) can authenticate against GitHub.
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

# This action is a no-op unless normal test execution has been delegated from RunPipeline via
# the useSeparateTestAction setting. In all other cases tests are executed inside RunPipeline.
if (-not $settings.useSeparateTestAction) {
    Write-Host "useSeparateTestAction is not enabled. Tests are executed by the RunPipeline action. Skipping."
    return
}

# Analyze the repository to determine the test folders (and other test related settings)
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting

# Resolve the container kept alive by the RunPipeline action.
# The container name is deterministic per project and is also exported to the environment by RunPipeline.
$containerName = $ENV:containerName
if (-not $containerName) {
    $containerName = GetContainerName($project)
}

# Credentials used to connect to the build container.
$credential = Get-TestRunnerCredential

# NOTE: RunTestsInBcContainer is the seam for the "local test runner". By default the
# BcContainerHelper test runner is used against the container created by RunPipeline; a
# custom/local test runner that behaves the same way can be provided as an override script.
$overrideParams = Get-ScriptOverrides -ALGoFolderName (Join-Path $projectPath ".AL-Go") -OverrideScriptNames @("RunTestsInBcContainer")

Invoke-AlGoTestRun `
    -settings $settings `
    -projectPath $projectPath `
    -containerName $containerName `
    -credential $credential `
    -installTestAppsJson $installTestAppsJson `
    -runTestsOverride $overrideParams['RunTestsInBcContainer']
