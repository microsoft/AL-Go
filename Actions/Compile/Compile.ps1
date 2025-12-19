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

$baseFolder = $ENV:GITHUB_WORKSPACE

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\.Modules\CompileFromWorkspace.psm1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
DownloadAndImportBcContainerHelper
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\DetermineProjectsToBuild\DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking


$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting
$settings = CheckAppDependencyProbingPaths -settings $settings -token $token -baseFolder $baseFolder -project $project

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

# COMPILE - Compiling apps and test apps 
$appFiles = @()
$appFiles = Build-AppsInWorkspace `
    -Folders $settings.appFolders `
    -CompilerFolder $compilerFolder `
    -OutFolder (Join-Path $projectFolder ".output") `
    -Ruleset (Join-Path $projectFolder $settings.rulesetFile -Resolve) `
    -Analyzers $analyzers `
    -BuildVersion $buildVersion `
    -MaxCpuCount $settings.workspaceCompilationParallelism `
    -PreCompileApp $precompileOverride `
    -PostCompileApp $postCompileOverride

$installApps += $appFiles
$appFolders = @()

$testAppFiles = @()
$testAppFiles = Build-AppsInWorkspace `
    -Folders $settings.testFolders `
    -CompilerFolder $compilerFolder `
    -OutFolder (Join-Path $projectFolder ".output") `
    -Ruleset (Join-Path $projectFolder $settings.rulesetFile -Resolve) `
    -Analyzers $analyzers `
    -BuildVersion $buildVersion `
    -MaxCpuCount $settings.workspaceCompilationParallelism `
    -PreCompileApp $precompileOverride `
    -PostCompileApp $postCompileOverride

$installTestApps += $testAppFiles
$testFolders = @()

# OUTPUT - Output the install apps and test apps as JSON
ConvertTo-Json $installApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installAppsJson
ConvertTo-Json $installTestApps -Depth 99 -Compress | Out-File -Encoding UTF8 -FilePath $installTestAppsJson