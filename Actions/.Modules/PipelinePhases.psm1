# PipelinePhases.psm1
#
# Modular build pipeline phases for AL-Go for GitHub.
#
# This module splits the monolithic RunPipeline (which delegates to Run-AlPipeline in
# BcContainerHelper) into three independently runnable phases that share a single
# development container within one GitHub Actions job:
#
#   New-AlGoDevEnvironment   -> create the BC container, install dependency apps and the test toolkit
#   Publish-AlGoApps         -> publish (and upgrade) the compiled apps into the container
#   Invoke-AlGoTests         -> run tests / BCPT tests / page scripting tests
#   Remove-AlGoDevEnvironment-> capture the event log and remove the container
#
# The phases only support the useCompilerFolder = true flow (compilation happens outside
# the container via the CompileApps action), which is what makes the container-only
# publish/test lifecycle separable. See Scenarios/ModularBuild.md for the design.
#
# Each phase drives public BcContainerHelper cmdlets directly, so no changes to
# BcContainerHelper / Run-AlPipeline are required. Cross-step state that cannot be
# re-derived (container credential, published apps) is persisted to a context file in
# RUNNER_TEMP via Save-PipelineContext / Restore-PipelineContext.

$errorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../AL-Go-Helper.ps1" -Resolve)

<#
.SYNOPSIS
    Returns the path to the pipeline context file for a project.
.DESCRIPTION
    The context file carries the small amount of cross-step state (container name,
    credential, artifact url, published apps) between the CreateDevEnvironment,
    PublishApps and RunTests actions, which run as separate processes in the same job.
.PARAMETER project
    The project folder ('.' for single-project repositories).
#>
function Get-PipelineContextPath {
    Param(
        [string] $project = '.'
    )
    $safeProject = "$project"
    if ($safeProject -eq '' -or $safeProject -eq '.') { $safeProject = 'root' }
    $safeProject = $safeProject -replace "[^a-zA-Z0-9\-]", '_'
    $tempFolder = "$ENV:RUNNER_TEMP"
    if (-not $tempFolder) { $tempFolder = [System.IO.Path]::GetTempPath() }
    return Join-Path $tempFolder "AlGoPipelineContext.$safeProject.json"
}

<#
.SYNOPSIS
    Persists the pipeline context to disk so the next phase (separate process) can read it.
.DESCRIPTION
    The container password is masked in the workflow log before the context is written.
    The context file lives in RUNNER_TEMP, which is scoped to a single job on an
    ephemeral runner.
.PARAMETER context
    The context hashtable to persist.
.PARAMETER project
    The project folder, used to compute the context file path.
#>
function Save-PipelineContext {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $context,
        [string] $project = '.'
    )
    $path = Get-PipelineContextPath -project $project
    if ($context.Keys -contains 'containerPassword' -and $context.containerPassword) {
        Write-Host "::add-mask::$($context.containerPassword)"
    }
    $context | ConvertTo-Json -Depth 50 | Set-Content -Path $path -Encoding UTF8
    OutputDebug -message "Saved pipeline context to $path"
    return $path
}

<#
.SYNOPSIS
    Restores the pipeline context persisted by a previous phase.
.PARAMETER project
    The project folder, used to compute the context file path.
#>
function Restore-PipelineContext {
    Param(
        [string] $project = '.'
    )
    $path = Get-PipelineContextPath -project $project
    if (-not (Test-Path $path)) {
        throw "Pipeline context file not found at '$path'. Ensure the CreateDevEnvironment action ran in the same job before this action."
    }
    $context = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -recurse
    if ($context.Keys -contains 'containerPassword' -and $context.containerPassword) {
        Write-Host "::add-mask::$($context.containerPassword)"
    }
    return $context
}

<#
.SYNOPSIS
    Reads AL-Go settings and secrets from the environment and builds the shared pipeline context.
.DESCRIPTION
    Factored out of RunPipeline.ps1 so that CreateDevEnvironment, PublishApps and RunTests
    all resolve settings, secrets and folder layout in exactly the same way. Secrets are
    decoded from $env:Secrets and are NOT written to the context file.
.PARAMETER token
    The GitHub token running the action.
.PARAMETER project
    The project folder ('.' for single-project repositories).
.PARAMETER buildMode
    The build mode used for the build steps.
.PARAMETER artifact
    Optional artifact URL override.
.OUTPUTS
    A hashtable with settings, decoded secret values, folder paths and the container name.
#>
function Initialize-PipelineContext {
    Param(
        [string] $token,
        [string] $project = '.',
        [string] $buildMode = 'Default',
        [string] $artifact = ''
    )

    if ($project -eq '.') { $project = '' }

    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
    if ($env:Secrets) {
        $secrets = $env:Secrets | ConvertFrom-Json | ConvertTo-HashTable -recurse
    }
    else {
        $secrets = @{}
    }

    $baseFolder = $ENV:GITHUB_WORKSPACE
    $projectPath = Join-Path $baseFolder $project
    $containerName = GetContainerName($project)

    $analyzeRepoParams = @{}
    if ($artifact) {
        $settings.artifact = $artifact
        $analyzeRepoParams += @{ "doNotCheckArtifactSetting" = $true }
    }
    $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project @analyzeRepoParams
    $settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

    # Modular build requires the compiler folder flow so compilation is decoupled from the container.
    Assert-ModularBuildSupported -settings $settings

    # Decode the secret values used across the phases (empty string when the secret is not present).
    $decodedSecrets = @{}
    'licenseFileUrl', 'codeSignCertificateUrl', 'codeSignCertificatePassword', 'keyVaultCertificateUrl', 'keyVaultCertificatePassword', 'keyVaultClientId', 'gitHubPackagesContext', 'applicationInsightsConnectionString' | ForEach-Object {
        if ($secrets.Keys -contains $_) {
            $decodedSecrets[$_] = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrets."$_"))
        }
        else {
            $decodedSecrets[$_] = ""
        }
    }

    $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"

    return @{
        "token"               = $token
        "project"             = $project
        "buildMode"           = $buildMode
        "settings"            = $settings
        "secrets"             = $decodedSecrets
        "baseFolder"          = $baseFolder
        "projectPath"         = $projectPath
        "buildArtifactFolder" = $buildArtifactFolder
        "containerName"       = $containerName
        "artifactUrl"         = $settings.artifact.replace('{INSIDERSASTOKEN}', '')
        "auth"                = 'UserPassword'
        "tenant"              = 'default'
        "companyName"         = $settings.companyName
    }
}

<#
.SYNOPSIS
    Throws when the current settings do not support the modular build flow.
.DESCRIPTION
    The modular build (CreateDevEnvironment / PublishApps / RunTests) requires
    useCompilerFolder = true so that compilation happens outside the container.
    useModularBuild is expected to enforce useCompilerFolder at settings-read time;
    this guard is the defense-in-depth check at run time.
.PARAMETER settings
    The resolved AL-Go settings hashtable.
#>
function Assert-ModularBuildSupported {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $settings
    )
    if (-not $settings.useCompilerFolder) {
        throw "The modular build actions (CreateDevEnvironment/PublishApps/RunTests) require 'useCompilerFolder' to be true. Enable 'useModularBuild' (which enforces 'useCompilerFolder') or use the classic RunPipeline action."
    }
}

<#
.SYNOPSIS
    Returns the compiled .app files produced by the CompileApps action for a phase.
.PARAMETER buildArtifactFolder
    The .buildartifacts folder for the project.
.PARAMETER subFolder
    'Apps' for apps, 'TestApps' for test/bcpt apps.
#>
function Get-CompiledApps {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $buildArtifactFolder,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Apps', 'TestApps', 'Dependencies')]
        [string] $subFolder
    )
    $folder = Join-Path $buildArtifactFolder $subFolder
    if (-not (Test-Path $folder)) {
        return @()
    }
    return @(Get-ChildItem -Path $folder -Filter '*.app' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}

<#
.SYNOPSIS
    Creates the Business Central development container and installs dependencies and the test toolkit.
.DESCRIPTION
    Phase 1 of the modular build. Creates the container with a known credential (persisted
    in the context so later phases can authenticate), installs dependency apps, and imports
    the test toolkit when tests will be run. Drives New-BcContainer,
    Set-BcContainerKeyVaultAadAppAndCertificate and Import-TestToolkitToBcContainer.
.PARAMETER context
    The pipeline context from Initialize-PipelineContext.
.PARAMETER installAppsJson
    Path to a JSON list of dependency apps to install.
.PARAMETER installTestAppsJson
    Path to a JSON list of dependency test apps to install.
.OUTPUTS
    The updated context hashtable (with credential and container metadata).
#>
function New-AlGoDevEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Container credentials require a plain-text derived SecureString')]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $context,
        [string] $installAppsJson = '',
        [string] $installTestAppsJson = ''
    )
    $settings = $context.settings
    $containerName = $context.containerName

    if ($settings.doNotPublishApps) {
        Write-Host "doNotPublishApps is set - skipping dev environment creation."
        $context.environmentCreated = $false
        return $context
    }

    if ($isWindows) {
        Assert-DockerIsRunning
    }

    # Generate a container credential and persist it so PublishApps / RunTests can authenticate.
    $password = GetRandomPassword
    Write-Host "::add-mask::$password"
    $credential = New-Object pscredential 'admin', (ConvertTo-SecureString -String $password -AsPlainText -Force)
    $context.containerPassword = $password

    $newBcContainerParams = @{
        "accept_eula"           = $true
        "accept_insiderEula"    = $true
        "containerName"         = $containerName
        "artifactUrl"           = $context.artifactUrl
        "Credential"            = $credential
        "auth"                  = $context.auth
        "updateHosts"           = $true
        "doNotCheckHealth"      = $true
        "enableTaskScheduler"   = [bool]$settings.enableTaskScheduler
        "assignPremiumPlan"     = [bool]$settings.assignPremiumPlan
    }
    if ($settings.memoryLimit) {
        $newBcContainerParams["memoryLimit"] = $settings.memoryLimit
    }

    Write-Host "Creating container $containerName"
    New-BcContainer @newBcContainerParams

    # Configure keyvault access for the container when a keyvault certificate is provided.
    if ($context.secrets.keyVaultCertificateUrl -and $context.secrets.keyVaultCertificatePassword -and $context.secrets.keyVaultClientId) {
        Write-Host "Enabling key vault access for the container"
        Set-BcContainerKeyVaultAadAppAndCertificate `
            -containerName $containerName `
            -pfxFile $context.secrets.keyVaultCertificateUrl `
            -pfxPassword (ConvertTo-SecureString -String $context.secrets.keyVaultCertificatePassword -AsPlainText -Force) `
            -clientId $context.secrets.keyVaultClientId
    }

    # Install dependency apps (already compiled elsewhere) so local apps can be published on top.
    $dependencyApps = @(Read-AppListFromJson -jsonPath $installAppsJson) + @(Get-CompiledApps -buildArtifactFolder $context.buildArtifactFolder -subFolder 'Dependencies')
    foreach ($app in ($dependencyApps | Select-Object -Unique)) {
        $appPath = "$app".Trim('()')
        if ($appPath -and (Test-Path $appPath)) {
            Write-Host "Publishing dependency app $(Split-Path $appPath -Leaf)"
            Publish-BcContainerApp -containerName $containerName -appFile $appPath -credential $credential -skipVerification -sync -install -useDevEndpoint:$false
        }
    }

    # Import the test toolkit when there are tests to build/run.
    $needsTestToolkit = (-not $settings.doNotRunTests) -or (-not $settings.doNotRunBcptTests) -or (@($settings.testFolders).Count -gt 0) -or (@($settings.bcptTestFolders).Count -gt 0)
    if ($needsTestToolkit) {
        $importParams = @{
            "containerName"            = $containerName
            "includeTestFrameworkOnly" = -not ([bool]$settings.installTestLibraries)
            "includeTestLibrariesOnly" = [bool]$settings.installTestLibraries
        }
        if ($settings.installPerformanceToolkit) {
            $importParams["includePerformanceToolkit"] = $true
        }
        Write-Host "Importing test toolkit"
        Import-TestToolkitToBcContainer @importParams
        $context.testToolkitInstalled = $true
    }

    # Install dependency test apps.
    $dependencyTestApps = @(Read-AppListFromJson -jsonPath $installTestAppsJson)
    foreach ($app in ($dependencyTestApps | Select-Object -Unique)) {
        $appPath = "$app".Trim('()')
        if ($appPath -and (Test-Path $appPath)) {
            Write-Host "Publishing dependency test app $(Split-Path $appPath -Leaf)"
            Publish-BcContainerApp -containerName $containerName -appFile $appPath -credential $credential -skipVerification -sync -install -useDevEndpoint:$false
        }
    }

    $context.environmentCreated = $true
    return $context
}

<#
.SYNOPSIS
    Publishes the compiled apps (and previous apps for upgrade) into the development container.
.DESCRIPTION
    Phase 2 of the modular build. Publishes app dependencies, previous apps (for data upgrade
    testing) and the compiled apps from .buildartifacts, then imports test data / config
    packages. Drives Publish-BcContainerApp and Sync/Install cmdlets.
.PARAMETER context
    The pipeline context (restored, then re-hydrated with the container credential).
.PARAMETER previousAppsPath
    Path to a folder with previously released apps for upgrade testing.
.OUTPUTS
    The updated context hashtable (with the list of published apps).
#>
function Publish-AlGoApps {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $context,
        [string] $previousAppsPath = ''
    )
    $settings = $context.settings
    $containerName = $context.containerName

    if ($settings.doNotPublishApps) {
        Write-Host "doNotPublishApps is set - skipping publishing."
        return $context
    }

    $credential = Get-PipelineCredential -context $context

    # Publish previous apps first (upgrade path) so the compiled apps upgrade them.
    if (-not $settings.skipUpgrade -and $previousAppsPath -and (Test-Path $previousAppsPath)) {
        $previousApps = @(Get-ChildItem -Path $previousAppsPath -Recurse -Filter '*.app' | ForEach-Object { $_.FullName })
        foreach ($app in $previousApps) {
            Write-Host "Publishing previous app $(Split-Path $app -Leaf) for upgrade"
            Publish-BcContainerApp -containerName $containerName -appFile $app -credential $credential -skipVerification -sync -install -useDevEndpoint:$false
        }
    }

    # Publish the compiled apps and test apps from .buildartifacts.
    $publishedApps = @()
    $apps = @(Get-CompiledApps -buildArtifactFolder $context.buildArtifactFolder -subFolder 'Apps')
    foreach ($app in $apps) {
        Write-Host "Publishing app $(Split-Path $app -Leaf)"
        Publish-BcContainerApp -containerName $containerName -appFile $app -credential $credential -skipVerification -sync -install -upgrade -useDevEndpoint:$false
        $publishedApps += $app
    }

    $testApps = @(Get-CompiledApps -buildArtifactFolder $context.buildArtifactFolder -subFolder 'TestApps')
    foreach ($app in $testApps) {
        Write-Host "Publishing test app $(Split-Path $app -Leaf)"
        Publish-BcContainerApp -containerName $containerName -appFile $app -credential $credential -skipVerification -sync -install -useDevEndpoint:$false
        $publishedApps += $app
    }

    $context.publishedApps = $publishedApps

    # Backup databases when the settings request a clean database between test runs.
    if ($settings.restoreDatabases) {
        Write-Host "Backing up databases"
        Backup-BcContainerDatabases -containerName $containerName
    }

    return $context
}

<#
.SYNOPSIS
    Runs tests, BCPT tests and page scripting tests in the development container.
.DESCRIPTION
    Phase 3 of the modular build. Drives Run-TestsInBcContainer and Run-BCPTTestsInBcContainer
    and writes JUnit results into .buildartifacts. Honors the doNotRunTests / doNotRunBcptTests /
    doNotRunPageScriptingTests settings.
.PARAMETER context
    The pipeline context (restored).
.OUTPUTS
    The updated context hashtable.
#>
function Invoke-AlGoTests {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $context
    )
    $settings = $context.settings
    $containerName = $context.containerName
    $projectPath = $context.projectPath

    # Mirror the monolithic RunPipeline behavior: when doNotPublishApps is set (e.g. workspace
    # compilation already produced the apps and this project is not published to a container),
    # RunPipeline exits before creating a container or running tests. No environment exists,
    # so there is nothing to test against here.
    if ($settings.doNotPublishApps) {
        Write-Host "doNotPublishApps is set - skipping tests (no development environment was created)."
        return $context
    }

    $credential = Get-PipelineCredential -context $context

    $testResultsFile = Join-Path $projectPath "TestResults.xml"
    $bcptTestResultsFile = Join-Path $projectPath "bcptTestResults.json"

    if (-not $settings.doNotRunTests -and @($settings.testFolders).Count -gt 0) {
        Write-Host "Running tests"
        Run-TestsInBcContainer `
            -containerName $containerName `
            -credential $credential `
            -companyName $context.companyName `
            -tenant $context.tenant `
            -XUnitResultFileName $testResultsFile `
            -AzureDevOps 'no' `
            -GitHubActions 'error' `
            -detailed `
            -returnTrueIfAllPassed
    }

    if (-not $settings.doNotRunBcptTests -and @($settings.bcptTestFolders).Count -gt 0) {
        Write-Host "Running BCPT tests"
        Run-BCPTTestsInBcContainer `
            -containerName $containerName `
            -credential $credential `
            -companyName $context.companyName `
            -tenant $context.tenant `
            -BCPTsuite (Get-BCPTSuiteFromFolders -folders $settings.bcptTestFolders) `
            -BCPTTestResultsFile $bcptTestResultsFile
    }

    return $context
}

<#
.SYNOPSIS
    Captures the container event log and removes the development container.
.DESCRIPTION
    Cleanup phase, invoked from the BuildAndTest composite as an always() step so it runs
    even when a previous phase failed. Honors keepEnvironment.
.PARAMETER context
    The pipeline context (restored).
.PARAMETER keepEnvironment
    When set, the container is left running (for debugging).
#>
function Remove-AlGoDevEnvironment {
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $context,
        [switch] $keepEnvironment
    )
    # When the dev environment was explicitly skipped (e.g. doNotPublishApps), no container was
    # ever created. Return before touching Test-BcContainer so we never probe the Docker API on
    # runners without a running Docker daemon (which would leak $LASTEXITCODE and fail the step).
    if ($context.ContainsKey('environmentCreated') -and (-not $context.environmentCreated)) {
        Write-Host "No development environment was created - skipping removal."
        return
    }
    $containerName = $context.containerName
    if (-not $containerName) {
        return
    }
    if (-not (Test-BcContainer -containerName $containerName)) {
        Write-Host "Container $containerName does not exist - nothing to remove."
        return
    }

    try {
        Write-Host "Getting event log from container $containerName"
        $eventLogFile = Get-BcContainerEventLog -containerName $containerName -doNotOpen
        $containerEventLogFile = Join-Path $context.projectPath "ContainerEventLog.evtx"
        Copy-Item -Path $eventLogFile -Destination $containerEventLogFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "Error getting event log from container: $($_.Exception.Message)"
    }

    if ($keepEnvironment) {
        Write-Host "keepEnvironment is set - leaving container $containerName running."
        return
    }

    Write-Host "Removing container $containerName"
    Remove-BcContainer -containerName $containerName
}

# --- internal helpers -------------------------------------------------------

<#
.SYNOPSIS
    Reconstructs the container PSCredential from the persisted context password.
#>
function Get-PipelineCredential {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Container credentials require a plain-text derived SecureString')]
    Param(
        [Parameter(Mandatory = $true)]
        [hashtable] $context
    )
    if (-not ($context.Keys -contains 'containerPassword') -or -not $context.containerPassword) {
        throw "Container credential not found in pipeline context. The CreateDevEnvironment action must run before this action."
    }
    Write-Host "::add-mask::$($context.containerPassword)"
    return New-Object pscredential 'admin', (ConvertTo-SecureString -String $context.containerPassword -AsPlainText -Force)
}

<#
.SYNOPSIS
    Reads a JSON-formatted list of app file paths, returning an empty array when absent.
#>
function Read-AppListFromJson {
    Param(
        [string] $jsonPath
    )
    if ($jsonPath -and (Test-Path $jsonPath)) {
        try {
            return @(Get-Content -Path $jsonPath -Raw | ConvertFrom-Json)
        }
        catch {
            throw "Failed to parse JSON file at path '$jsonPath'. Error: $($_.Exception.Message)"
        }
    }
    return @()
}

<#
.SYNOPSIS
    Generates a random password that satisfies Business Central container complexity rules.
#>
function GetRandomPassword {
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$%&*'
    $rnd = [System.Random]::new()
    $randomChars = -join (1..20 | ForEach-Object { $chars[$rnd.Next(0, $chars.Length)] })
    # Ensure at least one of each required character class.
    return "Aa1!$randomChars"
}

<#
.SYNOPSIS
    Returns the first bcptSuite.json found in the provided BCPT test folders.
#>
function Get-BCPTSuiteFromFolders {
    Param(
        [string[]] $folders
    )
    foreach ($folder in $folders) {
        $suite = Join-Path $folder 'bcptSuite.json'
        if (Test-Path $suite) {
            return (Get-Content -Path $suite -Raw | ConvertFrom-Json)
        }
    }
    return $null
}

Export-ModuleMember -Function Initialize-PipelineContext
Export-ModuleMember -Function Assert-ModularBuildSupported
Export-ModuleMember -Function New-AlGoDevEnvironment
Export-ModuleMember -Function Publish-AlGoApps
Export-ModuleMember -Function Invoke-AlGoTests
Export-ModuleMember -Function Remove-AlGoDevEnvironment
Export-ModuleMember -Function Save-PipelineContext
Export-ModuleMember -Function Restore-PipelineContext
Export-ModuleMember -Function Get-PipelineContextPath
Export-ModuleMember -Function Get-CompiledApps
