<#
    .SYNOPSIS
        Get the head ref from a PR
    .PARAMETER repository
        Repository to search in
    .PARAMETER prId
        The PR Id
    .PARAMETER token
        The GitHub token running the action
#>
function GetHeadRefFromPRId {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $prId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token

    $pullsURI = "https://api.github.com/repos/$repository/pulls/$prId"
    Write-Host "- $pullsURI"
    $pr = (InvokeWebRequest -Headers $headers -Uri $pullsURI).Content | ConvertFrom-Json

    return $pr.head.ref
}

<#
    .SYNOPSIS
        Get apps and dependencies from artifacts
    .PARAMETER token
        The GitHub token running the action
    .PARAMETER artifactsFolder
        The folder where artifacts are stored
    .PARAMETER deploymentSettings
        Deployment settings for the action
    .PARAMETER artifactsVersion
        Version of the artifacts to use (optional) - This is only used for PR deployments and should take the form of PR_X
    .PARAMETER buildMode
        The build mode to use (optional) - This is used to determine which build artifacts to use
#>
function GetAppsAndDependenciesFromArtifacts {
    Param(
        [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $artifactsFolder,
        [Parameter(Mandatory = $true)]
        [hashtable] $deploymentSettings,
        [Parameter(Mandatory = $false)]
        [string] $artifactsVersion = '',
        [Parameter(Mandatory = $false)]
        [string] $buildMode = ''
    )
    OutputDebugFunctionCall
    OutputGroupStart -Message "GetAppsAndDependenciesFromArtifacts"
    $apps = @()
    $dependencies = @()
    $artifactsFolder = Join-Path $ENV:GITHUB_WORKSPACE $artifactsFolder
    $TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"
    if (Test-Path $artifactsFolder -PathType Container) {
        $deploymentSettings.Projects.Split(',') | ForEach-Object {
            $project = $_.Replace('\','_').Replace('/','_')
            $artifactVersionFilter = '*.*.*.*'
            $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
            # Artifacts from PRs are named differently - project-ref-Apps-PRx-date
            if ($artifactsVersion -like "PR_*") {
                $prId = $artifactsVersion.SubString(3)
                $intId = 0
                if (!([Int]::TryParse($prId, [ref] $intId))) {
                    OutputGroupEnd
                    throw "Invalid PR id: $prId"
                }
                $artifactVersionFilter = "PR$prId-*"
                $refname = (GetHeadRefFromPRId -repository $ENV:GITHUB_REPOSITORY -prId $prId -token $token).Replace('/','_')
            }
            Write-Host "project '$project'"

            $allApps = @()
            OutputDebug -message "projectApps filter: $project-$refname-$($buildMode)Apps-$artifactVersionFilter"
            $projectApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildMode)Apps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
            $projectTestApps = @()
            if ($deploymentSettings.includeTestAppsInSandboxEnvironment) {
                Write-Host "Including test apps for deployment"
                OutputDebug -message "projectTestApps filter: $project-$refname-$($buildMode)TestApps-$artifactVersionFilter"
                $projectTestApps = @((Get-ChildItem -Path $artifactsFolder -Filter "$project-$refname-$($buildMode)TestApps-$artifactVersionFilter") | ForEach-Object { $_.FullName })
            }
            if ($deploymentSettings.excludeAppIds) {
                Write-Host "Excluding apps with ids $($deploymentSettings.excludeAppIds) from deployment"
            }
            if ($deploymentSettings.DependencyInstallMode -ne "ignore") {
                OutputDebug -message "projectDependencies filter: $project-$refname-$($buildMode)Dependencies-$artifactVersionFilter/*.app"
                $dependencies += @((Get-ChildItem -Path (Join-Path $artifactsFolder "$project-$refname-$($buildMode)Dependencies-$artifactVersionFilter/*.app")) | ForEach-Object { $_.FullName } )
            }
            if (!($projectApps)) {
                if ($project -ne '*') {
                    OutputGroupEnd
                    throw "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildMode)Apps-<version>."
                }
            }
            else {
                $allApps += $projectApps
            }
            if ($deploymentSettings.includeTestAppsInSandboxEnvironment -and !($projectTestApps)) {
                if ($project -ne '*') {
                    OutputWarning -message "There are no artifacts present in $artifactsFolder matching $project-$refname-$($buildMode)TestApps-<version>."
                }
            }
            else {
                $allApps += $projectTestApps
            }
            # Go through all .app files and exclude any with ids in the excludeAppIds list
            # Also exclude apps with direct dependencies on Tests-TestLibraries
            if ($allApps) {
                foreach($folder in $allApps) {
                    foreach($app in (Get-ChildItem -Path $folder -Filter "*.app")) {
                        Write-Host "Processing app: $($app.Name)"
                        $appJson = Get-AppJsonFromAppFile -appFile $app.FullName
                        if ($appJson.id -notin $deploymentSettings.excludeAppIds) {
                            # If app should be included, verify that it does not depend on Tests-TestLibraries
                            $unknownDependenciesForApp = @()
                            Sort-AppFilesByDependencies -appFiles @($app.FullName) -unknownDependencies ([ref]$unknownDependenciesForApp) -WarningAction SilentlyContinue | Out-Null
                            $unknownDependenciesForApp | ForEach-Object {
                                if ($_.Split(':')[0] -eq $TestsTestLibrariesAppId) {
                                    OutputWarning -message "Test-TestLibraries can't be installed - skipping app $($app.Name)"
                                    continue
                                }
                            }

                            $apps += $app.FullName
                            Write-Host "App $($app.Name) with id $($appJson.id) included in deployment"
                        }
                        else {
                            Write-Host "App $($app.Name) with id $($appJson.id) excluded from deployment"
                        }
                    }
                }
            }
        }
    }
    else {
        OutputGroupEnd
        throw "Artifact $artifactsFolder was not found. Make sure that the artifact files exist and files are not corrupted."
    }
    OutputGroupEnd
    return $apps, $dependencies
}
