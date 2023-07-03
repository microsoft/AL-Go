Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
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

    import-module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0079' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $settings = ReadSettings -baseFolder $baseFolder -project $project
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    if ($ENV:GITHUB_EVENT_NAME -in @("pull_request_target", "pull_request")) {
        $settings.doNotSignApps = $true
        $settings.versioningStrategy = 15
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

    if ($getenvironments) {
        $environments = @()
        $headers = @{ 
            "Authorization"        = "token $token"
            "Accept"               = "application/vnd.github.v3+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        Write-Host "Requesting environments: $getEnvironments"
        $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"
        try {
            Write-Host "Trying to get environments from GitHub API"
            $ghEnvironments = @((InvokeWebRequest -Headers $headers -Uri $url -ignoreErrors | ConvertFrom-Json).environments | Where-Object { $_.name -like $getEnvironments })
        } 
        catch {
            $ghEnvironments = @()
            Write-Host "Failed to get environments from GitHub API - Environments are not supported in this repository"
        }
        Write-Host "Requesting environments from settings"
        $environments = @(@($ghEnvironments | ForEach-Object { $_.name })+@($settings.environments) | Select-Object -unique | Where-Object { $_ -ne "github-pages" })
        $unknownEnvironment = 0
        if (!($environments)) {
            $unknownEnvironment = 1
            # If no environments are defined and the user specified a single environment, use that environment
            # This allows the user to specify a single environment without having to define it in the settings
            if ($getenvironments -notcontains '*' -and $getenvironments -notcontains '?' -and $getenvironments -notcontains ',') {
                $environments = @($getenvironments)
            }
        }
        else {
            if ($environments) {
                Write-Host "Environments found: $($environments -join ', ')"
            }
            $environments = @($environments | Where-Object { 
                if ($includeProduction) {
                    $_ -like $getEnvironments -or $_ -like "$getEnvironments (PROD)" -or $_ -like "$getEnvironments (Production)" -or $_ -like "$getEnvironments (FAT)" -or $_ -like "$getEnvironments (Final Acceptance Test)"
                }
                else {
                    $_ -like $getEnvironments -and $_ -notlike '* (PROD)' -and $_ -notlike '* (Production)' -and $_ -notlike '* (FAT)' -and $_ -notlike '* (Final Acceptance Test)'
                }
            } | Where-Object {
                $envName = $_
                Write-Host "Environment: $envName"
                $ghEnvironment = $ghEnvironments | Where-Object { $_.name -eq $envName }
                if ($ghEnvironment) {
                    $branchPolicy = ($ghEnvironment.protection_rules | Where-Object { $_.type -eq "branch_policy" })
                    if ($branchPolicy) {
                        Write-Host "GitHub Environment $envName has branch policies, getting branches from GitHub API"
                        $branchesUrl = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments/$([Uri]::EscapeDataString($envName))/deployment-branch-policies"
                        Write-Host "Getting branches for $envName from GitHub API"
                        $branches = @((InvokeWebRequest -Headers $headers -Uri $branchesUrl -ignoreErrors | ConvertFrom-Json).branch_policies | ForEach-Object { $_.name })
                    }
                    else {
                        Write-Host "GitHub Environment $envName does not have branch policies, using main as default"
                        $branches = @( 'main' )
                    }
                }
                else {
                    Write-Host "Environment $envName was defined in settings, using main as default"
                    $branches = @( 'main' )
                }
                $environmentName = $_.Split(' ')[0]
                $deployToName = "DeployTo$environmentName"
                if (($settings.Contains($deployToName)) -and ($settings."$deployToName".Contains('Branches'))) {
                    $branches = @($settings."$deployToName".Branches)
                }
                Write-Host "- branches: $($branches -join ', ')"
                $includeEnvironment = $false
                $branches | ForEach-Object {
                    if ($ENV:GITHUB_REF_NAME -like $_) {
                        $includeEnvironment = $true
                    }
                }
                Write-Host "- include: $includeEnvironment"
                $includeEnvironment
            })
        }
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
        Add-Content -Path $env:GITHUB_OUTPUT -Value "UnknownEnvironment=$unknownEnvironment"
        Write-Host "UnknownEnvironment=$unknownEnvironment"
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
