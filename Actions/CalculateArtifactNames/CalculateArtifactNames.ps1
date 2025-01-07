Param(
    [Parameter(HelpMessage = "Name of the built project", Mandatory = $true)]
    [string] $project,
    [Parameter(HelpMessage = "Build mode used when building the artifacts", Mandatory = $true)]
    [string] $buildMode,
    [Parameter(HelpMessage = "Suffix to add to the artifacts names", Mandatory = $false)]
    [string] $suffix
)

function Set-OutputVariable([string] $name, [string] $value) {
    Write-Host "Assigning $value to $name"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "$name=$value"
}

$settings = $env:Settings | ConvertFrom-Json

if ($project -eq ".") {
    $project = $settings.repoName
}

$branchName = $ENV:GITHUB_HEAD_REF
# $ENV:GITHUB_HEAD_REF is specified only for pull requests, so if it is not specified, use GITHUB_REF_NAME
if (!$branchName) {
    $branchName = $ENV:GITHUB_REF_NAME
}

$branchName = $branchName.Replace('\', '_').Replace('/', '_')
$projectName = $project.Replace('\', '_').Replace('/', '_')

# If the buildmode is default, then we don't want to add it to the artifact name
if ($buildMode -eq 'Default') {
    $buildMode = ''
}
Set-OutputVariable -name "BuildMode" -value $buildMode

if ($suffix) {
    # Add the date to the suffix
    $suffix = "$suffix-$([DateTime]::UtcNow.ToString('yyyyMMdd'))"
}
else {
    $repoVersion = [System.Version]$settings.repoVersion
    $appBuild = $settings.appBuild
    if ($appBuild -eq -1) {
        $appBuild = $repoVersion.Build
        if ($repoVersion.Build -eq -1) {
            $appBuild = 0
        }
    }
    $suffix = "$($repoVersion.Major).$($repoVersion.Minor).$($appBuild).$($settings.appRevision)"
}

'Apps', 'Dependencies', 'TestApps', 'TestResults', 'BcptTestResults', 'PageScriptingTestResults', 'PageScriptingTestResultDetails', 'BuildOutput', 'ContainerEventLog', 'PowerPlatformSolution' | ForEach-Object {
    $name = "$($_)ArtifactsName"
    $value = "$($projectName)-$($branchName)-$buildMode$_-$suffix"
    Set-OutputVariable -name $name -value $value
}

# Set this build artifacts name
'Apps', 'Dependencies', 'TestApps' | ForEach-Object {
    $name = "ThisBuild$($_)ArtifactsName"
    $value = "thisbuild-$($projectName)-$($buildMode)$($_)"
    Set-OutputVariable -name $name -value $value
}
