Param(
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "ArtifactUrl to use for the build", Mandatory = $false)]
    [string] $artifact = "",
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Specifies a mode to use for the build steps", Mandatory = $false)]
    [string] $buildMode = 'Default',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of apps to install", Mandatory = $false)]
    [string] $installAppsJson = '',
    [Parameter(HelpMessage = "A path to a JSON-formatted list of test apps to install", Mandatory = $false)]
    [string] $installTestAppsJson = '',
    [Parameter(HelpMessage = "RunId of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowRunId = '0',
    [Parameter(HelpMessage = "SHA of the baseline workflow run", Mandatory = $false)]
    [string] $baselineWorkflowSHA = ''
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot "..\.Modules\CompileFromWorkspace.psm1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot '.\Compile.psm1' -Resolve)
DownloadAndImportBcContainerHelper
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking

$baseFolder = $ENV:GITHUB_WORKSPACE
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting
$settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

if ($settings.appFolders.Count -eq 0 -and $settings.testFolders.Count -eq 0) {
    Write-Host "No app folders or test app folders specified for compilation. Skipping compilation step."
    return
}

#TODO
$projectFolder = Join-Path $baseFolder $project
Set-Location $projectFolder
$analyzers = @()
$buildVersion = "28.0.0.0"
$precompileOverride = $null
$postCompileOverride = $null

# Set up a compiler folder 
$containerName = GetContainerName($project)
$compilerFolder = New-BcCompilerFolder -artifactUrl $artifact -containerName "$($containerName)compiler"

$installApps = $settings.installApps
$installTestApps = $settings.installTestApps

if ($installAppsJson -and (Test-Path $installAppsJson)) {
    try {
        $installApps += @(Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse JSON file at path '$installAppsJson'. Error: $($_.Exception.Message)"
    }
}

if ($installTestAppsJson -and (Test-Path $installTestAppsJson)) {
    try {
        $installTestApps += @(Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse JSON file at path '$installTestAppsJson'. Error: $($_.Exception.Message)"
    }
}

$buildArtifactFolder = Join-Path $projectFolder ".buildartifacts"
New-Item $buildArtifactFolder -ItemType Directory | Out-Null
$appOutputFolder = Join-Path $buildArtifactFolder "Apps"
New-Item $appOutputFolder -ItemType Directory | Out-Null
$testAppOutputFolder = Join-Path $buildArtifactFolder "TestApps"
New-Item $testAppOutputFolder -ItemType Directory | Out-Null

try {
    $sourceRepositoryUrl = "$ENV:GITHUB_SERVER_URL/$ENV:GITHUB_REPOSITORY"
    $sourceCommit = $ENV:GITHUB_SHA

    $preprocessorSymbols = @()
    if ($settings.ContainsKey('preprocessorSymbols')) {
        Write-Host "Adding Preprocessor symbols : $($settings.preprocessorSymbols -join ',')"
        $preprocessorSymbols += $settings.preprocessorSymbols
    }

    $features = @()
    if ($settings.ContainsKey('features')) {
        Write-Host "Adding features : $($settings.features -join ',')"
        $features += $settings.features
    }

    if ($settings.appFolders.Count -gt 0) {
        # COMPILE - Compiling apps and test apps
        $appFiles = @()

        # TODO: Missing in compiler buildBy, buildUrl, generatecrossreferences, ReportSuppressedDiagnostics, generateErrorLog
        # TODO: Missing handling of incrementalBuilds
        # TODO: (Maybe) Missing implementation of around using latest release as a baseline (skipUpgrade)
        # TODO: Missing appBuildnumber implementation (could be its own action?)
        # TODO: Missing downloading of external dependencies (should probably be a separate action)
        $appFiles = Build-AppsInWorkspace `
            -Folders $settings.appFolders `
            -CompilerFolder $compilerFolder `
            -OutFolder $appOutputFolder `
            -Ruleset (Join-Path $projectFolder $settings.rulesetFile -Resolve) `
            -Analyzers $analyzers `
            -Preprocessorsymbols $preprocessorSymbols `
            -Features $features `
            -BuildVersion $buildVersion `
            -MaxCpuCount $settings.workspaceCompilationParallelism `
            -SourceRepositoryUrl $sourceRepositoryUrl `
            -SourceCommit $sourceCommit `
            -PreCompileApp $precompileOverride `
            -PostCompileApp $postCompileOverride

        $installApps += $appFiles
    }

    if ($settings.testFolders.Count -gt 0) {
        $testAppFiles = @()
        $testAppFiles = Build-AppsInWorkspace `
            -Folders $settings.testFolders `
            -CompilerFolder $compilerFolder `
            -OutFolder $testAppOutputFolder `
            -Ruleset (Join-Path $projectFolder $settings.rulesetFile -Resolve) `
            -Analyzers $analyzers `
            -Preprocessorsymbols $preprocessorSymbols `
            -Features $features `
            -BuildVersion $buildVersion `
            -MaxCpuCount $settings.workspaceCompilationParallelism `
            -SourceRepositoryUrl $sourceRepositoryUrl `
            -SourceCommit $sourceCommit `
            -PreCompileApp $precompileOverride `
            -PostCompileApp $postCompileOverride

        $installTestApps += $testAppFiles
    }
} finally {
    New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath (Join-Path $projectFolder "BuildOutput.txt") -DisplayInConsole
}

# OUTPUT - Output the install apps and test apps as JSON
ConvertTo-Json $installApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installAppsJson
ConvertTo-Json $installTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installTestAppsJson