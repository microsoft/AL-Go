Param(
    [Parameter(HelpMessage = "The folder to scan for projects to build", Mandatory = $true)]
    [string] $baseFolder,
    [Parameter(HelpMessage = "The maximum depth to build the dependency tree", Mandatory = $false)]
    [int] $maxBuildDepth = 0,
    [Parameter(HelpMessage = "The GitHub token to use to fetch the modified files", Mandatory = $true)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d'
)

$telemetryScope = $null

try {
    #region Action: Setup
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

    DownloadAndImportBcContainerHelper -baseFolder $baseFolder
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve) -DisableNameChecking
    #endregion

    $telemetryScope = CreateScope -eventId 'DO0085' -parentTelemetryScopeJson $parentTelemetryScopeJson

    #region Action: Determine projects to build
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking

    Write-Host "::group::Get Modified Files"
    $modifiedFiles = Get-ModifiedFiles -token $token
    Write-Host "$($modifiedFiles.Count) modified file(s): $($modifiedFiles -join ', ')"
    Write-Host "::endgroup::"

    Write-Host "::group::Determine Partial Build"
    $isPartialBuild = -Get-IsPatialBuild -modifiedFiles $modifiedFiles -baseFolder $baseFolder
    Write-Host "::endgroup::"

    Write-Host "::group::Get Projects To Build"
    $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -isPartialBuild $isPartialBuild -modifiedFiles $modifiedFiles -maxBuildDepth $maxBuildDepth
    AddTelemetryProperty -telemetryScope $telemetryScope -key "projects" -value "$($allProjects -join ', ')"
    Write-Host "::endgroup::"
    #endregion

    #region Action: Output
    $projectsJson = ConvertTo-Json $projectsToBuild -Depth 99 -Compress
    $projectDependenciesJson = ConvertTo-Json $projectDependencies -Depth 99 -Compress
    $buildOrderJson = ConvertTo-Json $buildOrder -Depth 99 -Compress
    $IsPartialBuildJson = ConvertTo-Json $IsPartialBuild -Depth 99 -Compress

    # Set output variables
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ProjectsJson=$projectsJson"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "ProjectDependenciesJson=$projectDependenciesJson"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "BuildOrderJson=$buildOrderJson"
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "IsPartialBuild=$IsPartialBuildJson"

    Write-Host "ProjectsJson=$projectsJson"
    Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
    Write-Host "BuildOrderJson=$buildOrderJson"
    Write-Host "IsPartialBuildJson=$isPartialBuildJson"
    #endregion

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
