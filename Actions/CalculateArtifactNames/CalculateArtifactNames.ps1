Param(
    [Parameter(HelpMessage = "Name of the built project", Mandatory = $true)]
    [string] $project,
    [Parameter(HelpMessage = "Build mode used when building the artifacts", Mandatory = $true)]
    [string] $buildMode,
    [Parameter(HelpMessage = "Name of the branch the workflow is running on", Mandatory = $true)]
    [string] $branchName,
    [Parameter(HelpMessage = "Suffix to add to the artifacts names", Mandatory = $false)]
    [string] $suffix
)

function Set-OutputVariable([string] $name, [string] $value) {
    Write-Host "Assigning $value to $name"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "$name=$value"
}

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch
# IMPORTANT: All actions needs a try/catch here and not only in the yaml file, else they can silently fail

try {
    $settings = $env:Settings | ConvertFrom-Json

    if ($project -eq ".") {
        $project = $settings.repoName
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
        # Default suffix is the build number
        $suffix = "$($settings.repoVersion).$($settings.appBuild).$($settings.appRevision)"
    }

    'Apps', 'Dependencies', 'TestApps', 'TestResults', 'BcptTestResults', 'BuildOutput', 'ContainerEventLog' | ForEach-Object {
        $name = "$($_)ArtifactsName"
        $value = "$($projectName)-$($branchName)-$buildMode$_-$suffix"
        Set-OutputVariable -name $name -value $value
    }

    # Set this build artifacts name
    'Apps', 'TestApps' | ForEach-Object {
        $name = "ThisBuild$($_)ArtifactsName"
        $value = "thisbuild-$($projectName)-$($buildMode)$($_)"
        Set-OutputVariable -name $name -value $value
    }
}
catch {
    Write-Host "::ERROR::AnalyzeTests action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    $host.SetShouldExit(1)
}
