Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Indicates whether you want to retrieve the list of project list as well", Mandatory = $false)]
    [bool] $getProjects,
    [Parameter(HelpMessage = "Specifies the pattern of the environments you want to retreive (or empty for no environments)", Mandatory = $false)]
    [string] $getenvironments = "",
    [Parameter(HelpMessage = "Specifies whether you want to include production environments", Mandatory = $false)]
    [bool] $includeProduction,
    [Parameter(HelpMessage = "Indicates whether this is called from a release pipeline", Mandatory = $false)]
    [bool] $release,
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    $baseFolder = $ENV:GITHUB_WORKSPACE
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0079' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $settings = ReadSettings -baseFolder $baseFolder -project $project
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    if ($ENV:GITHUB_EVENT_NAME -eq "pull_request") {
        $settings.doNotSignApps = $true
    }

    if ($settings.appBuild -eq [int32]::MaxValue) {
        $settings.versioningStrategy = 15
    }

    if ($settings.versioningstrategy -ne -1) {
        if ($getSettings -contains 'appBuild' -or $getSettings -contains 'appRevision') {
            switch ($settings.versioningStrategy -band 15) {
                0 { # Use RUN_NUMBER and RUN_ATTEMPT
                    $settings.appBuild = $settings.runNumberOffset + [Int32]($ENV:GITHUB_RUN_NUMBER)
                    $settings.appRevision = [Int32]($ENV:GITHUB_RUN_ATTEMPT) - 1
                }
                1 { # Use RUN_ID and RUN_ATTEMPT
                    OutputError -message "Versioning strategy 1 is no longer supported"
                }
                2 { # USE DATETIME
                    $settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))
                    $settings.appRevision = [Int32]([DateTime]::UtcNow.ToString('HHmmss'))
                }
                15 { # Use maxValue
                    $settings.appBuild = [Int32]::MaxValue
                    $settings.appRevision = 0
                }
                default {
                    OutputError -message "Unknown version strategy $versionStrategy"
                    exit
                }
            }
        }
    }

    $outSettings = @{}
    $getSettings | ForEach-Object {
        $setting = $_.Trim()
        $settingValue = $settings."$setting"
        $outSettings += @{ "$setting" = $settingValue }
        if ($settingValue -is [System.Collections.Specialized.OrderedDictionary]) {
            Add-Content -Path $env:GITHUB_ENV -Value "$setting=$($settingValue | ConvertTo-Json -Depth 99 -Compress)"
        }
        else {
            Add-Content -Path $env:GITHUB_ENV -Value "$setting=$settingValue"
        }
    }

    $outSettingsJson = $outSettings | ConvertTo-Json -Depth 99 -Compress
    Add-Content -Path $env:GITHUB_OUTPUT -Value "SettingsJson=$outSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"
    Write-Host "SettingsJson=$outSettingsJson"

    $gitHubRunner = $settings.githubRunner.Split(',').Trim() | ConvertTo-Json -compress
    Add-Content -Path $env:GITHUB_OUTPUT -Value "GitHubRunnerJson=$githubRunner"
    Write-Host "GitHubRunnerJson=$githubRunner"

    $gitHubRunnerShell = $settings.githubRunnerShell
    Add-Content -Path $env:GITHUB_OUTPUT -Value "GitHubRunnerShell=$githubRunnerShell"
    Write-Host "GitHubRunnerShell=$githubRunnerShell"

    # Add only default build mode if not specified in settings
    if (!$settings.buildModes) {
        $settings.buildModes = @("Default")
    }

    if ($settings.buildModes.Count -eq 1) {
        $buildModes = "[$($settings.buildModes | ConvertTo-Json -compress)]"
    }
    else {
        $buildModes = $settings.buildModes | ConvertTo-Json -compress
    }
    
    Add-Content -Path $env:GITHUB_OUTPUT -Value "BuildModes=$buildModes"
    Write-Host "BuildModes=$buildModes"

    function Get-ChangedFiles($token) {
        $headers = @{             
            "Authorization" = "token $token"
            "Accept" = "application/vnd.github.baptiste-preview+json"
        }
        $ghEvent = Get-Content $ENV:GITHUB_EVENT_PATH -encoding UTF8 | ConvertFrom-Json

        if (($ENV:GITHUB_EVENT_NAME -eq "pull_request") -or ($ENV:GITHUB_EVENT_NAME -eq "pull_request_target")) {
            $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/compare/$($ghEvent.pull_request.base.sha)...$($ENV:GITHUB_SHA)"
        } else {
            $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/compare/$($ghEvent.before)...$($ghEvent.after)"
        }

        if ($ghEvent.before -eq '0'*40) {
            $filesChanged = @()
        } else {
            $response = InvokeWebRequest -Headers $headers -Uri $url | ConvertFrom-Json
            $filesChanged = @($response.files | ForEach-Object { $_.filename })
        }

        return $filesChanged
    }

    function Get-ProjectsToBuild($settings, $projects, $baseFolder, $token) {
        if ($settings.alwaysBuildAllProjects) {
            Write-Host "Building all projects because alwaysBuildAllProjects is set to true"
            return $projects
        } elseif ($ENV:GITHUB_WORKFLOW -eq 'CICD') {
            Write-Host "Building all projects because this is a CICD run"
            return $projects
        }
        else {
            $filesChanged = @(Get-ChangedFiles -token $token)
            if ($filesChanged.Count -eq 0) {
                Write-Host "Building all projects"
                return $projects
            }
            elseif ($filesChanged -like '.github/*.json') {
                Write-Host "Changes to Repo Settings, building all projects"
                return $projects
            }
            elseif ($filesChanged.Count -ge 250) {
                Write-Host "More than 250 files modified, building all projects"
                return $projects
            }
            else {
                Write-Host "Modified files:"
                $buildProjects = @()
                $filesChanged | Out-Host
                $buildProjects = @($projects | Where-Object {
                    $checkProject = $_
                    $buildProject = $false
                    if (Test-Path -path (Join-Path $baseFolder "$checkProject/.AL-Go/settings.json")) {
                        $projectFolders = Get-ProjectFolders -baseFolder $baseFolder -project $checkProject -token $token -includeAlGoFolder -includeApps -includeTestApps
                        $projectFolders | ForEach-Object {
                            if ($filesChanged -like "$_/*") { $buildProject = $true }
                        }
                    }
                    $buildProject
                })
                Write-Host "Modified projects: $($buildProjects -join ', ')"
                return $buildProjects
            }
        }
    }

    if ($getProjects) {
        Write-Host "Determining projects to build"
        $buildProjects = @()
        if ($settings.projects) {
            $projects = $settings.projects
        }
        else {
            $projects = @(Get-ChildItem -Path $baseFolder -Recurse -Depth 2 | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName ".AL-Go/settings.json") -PathType Leaf) } | ForEach-Object { $_.FullName.Substring($baseFolder.length+1) })
        }

        if ($projects) {
            AddTelemetryProperty -telemetryScope $telemetryScope -key "projects" -value "$($projects -join ', ')"
            Write-Host "All Projects: $($projects -join ', ')"
            $buildProjects += Get-ProjectsToBuild -settings $settings -projects $projects -baseFolder $baseFolder -token $token
            
            if ($settings.useProjectDependencies) {
                $buildAlso = @{}
                $buildOrder = @{}
                $projectDependencies = @{}
                AnalyzeProjectDependencies -baseFolder $baseFolder -projects $projects -buildOrder ([ref]$buildOrder) -buildAlso ([ref]$buildAlso) -projectDependencies ([ref]$projectDependencies)
                $buildProjects = @($buildProjects | ForEach-Object { $_; if ($buildAlso.Keys -contains $_) { $buildAlso."$_" } } | Select-Object -Unique)
                Write-Host "Building projects: $($buildProjects -join ', ')"
                $projectDependenciesJson = $projectDependencies | ConvertTo-Json -Compress
                $buildOrderJson = $buildOrder | ConvertTo-Json -Compress
                Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectDependenciesJson=$projectDependenciesJson"
                Add-Content -Path $env:GITHUB_OUTPUT -Value "BuildOrderJson=$buildOrderJson"
                Add-Content -Path $env:GITHUB_OUTPUT -Value "BuildOrderDepth=$($buildOrder.Count)"
                Write-Host "ProjectDependenciesJson=$projectDependenciesJson"
                Write-Host "BuildOrderJson=$buildOrderJson"
                Write-Host "BuildOrderDepth=$($buildOrder.Count)"
            }
        }
        Write-Host "Projects to build: $($buildProjects -join ', ')"
        Write-Host $buildProjects
        if (Test-Path (Join-Path ".AL-Go" "settings.json") -PathType Leaf) {
            $buildProjects += @(".")
        }
        if ($buildProjects.Count -eq 1) {
            $projectsJSon = "[$($buildProjects | ConvertTo-Json -compress)]"
        }
        else {
            $projectsJSon = $buildProjects | ConvertTo-Json -compress
        }
        Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectsJson=$projectsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "projects=$projectsJson"
        Write-Host "ProjectsJson=$projectsJson"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "ProjectCount=$($buildProjects.Count)"
        Write-Host "ProjectCount=$($buildProjects.Count)"
    }

    if ($getenvironments) {
        $environments = @()
        $headers = @{ 
            "Authorization" = "token $token"
            "Accept"        = "application/vnd.github.v3+json"
        }
        $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"
        try {
            Write-Host "Trying to get environments from GitHub API"
            $environments = @((InvokeWebRequest -Headers $headers -Uri $url -ignoreErrors | ConvertFrom-Json).environments | ForEach-Object { $_.Name })
        } 
        catch {
            Write-Host "Failed to get environments from GitHub API - Environments are not supported in this repository"
        }
        $environments = @($environments+@($settings.environments) | Where-Object { $_ -ne "github-pages" } | Where-Object { 
            if ($includeProduction) {
                $_ -like $getEnvironments -or $_ -like "$getEnvironments (PROD)" -or $_ -like "$getEnvironments (Production)" -or $_ -like "$getEnvironments (FAT)" -or $_ -like "$getEnvironments (Final Acceptance Test)"
            }
            else {
                $_ -like $getEnvironments -and $_ -notlike '* (PROD)' -and $_ -notlike '* (Production)' -and $_ -notlike '* (FAT)' -and $_ -notlike '* (Final Acceptance Test)'
            }
        } | Where-Object {
            $branches = @( 'main' )
            $environmentName = $_.Split(' ')[0]
            $deployToName = "DeployTo$environmentName"
            if (($settings.Contains($deployToName)) -and ($settings."$deployToName".Contains('Branches'))) {
                $branches = @($settings."$deployToName".Branches)
            }
            $branches | Out-Host
            $includeEnvironment = $false
            $branches | ForEach-Object {
                if ($ENV:GITHUB_REF_NAME -like $_) {
                    $includeEnvironment = $true
                }
            }
            $includeEnvironment
        })

        $json = @{"matrix" = @{ "include" = @() }; "fail-fast" = $false }
        $environments | Select-Object -Unique | ForEach-Object { 
            $environmentName = $_.Split(' ')[0]
            $deployToName = "DeployTo$environmentName"
            $runson = $settings."runs-on".Split(',').Trim()
            if (($settings.Contains($deployToName)) -and ($settings."$deployToName".Contains('runs-on'))) {
                $runson = $settings."$deployToName"."runs-on"
            }
            $json.matrix.include += @{ "environment" = $_; "os" = "$($runson | ConvertTo-Json -compress)" }
        }
        $environmentsJson = $json | ConvertTo-Json -Depth 99 -compress
        Add-Content -Path $env:GITHUB_OUTPUT -Value "EnvironmentsJson=$environmentsJson"
        Add-Content -Path $env:GITHUB_ENV -Value "environments=$environmentsJson"
        Write-Host "EnvironmentsJson=$environmentsJson"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "EnvironmentCount=$($environments.Count)"
        Write-Host "EnvironmentCount=$($environments.Count)"
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "ReadSettings action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
