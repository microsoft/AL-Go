Param(
    [Parameter(HelpMessage = "Specifies the pattern of the environments you want to retreive (* for all)", Mandatory = $true)]
    [string] $getEnvironments,
    [Parameter(HelpMessage = "Type of deployment (CD or Publish)", Mandatory = $false)]
    [ValidateSet('CD','Publish')]
    [string] $type = "CD"
)

function GetGitHubEnvironments() {
    $headers = GetHeader -token $env:GITHUB_TOKEN
    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"
    try {
        Write-Host "Requesting environments from GitHub"
        $ghEnvironments = @((InvokeWebRequest -Headers $headers -Uri $url -ignoreErrors | ConvertFrom-Json).environments)
    }
    catch {
        $ghEnvironments = @()
        Write-Host "Failed to get environments from GitHub API - Environments are not supported in this repository"
    }
    $ghEnvironments
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse
Write-Host "Environment pattern to use: $getEnvironments"
$ghEnvironments = @(GetGitHubEnvironments)

# Include custom deployment environments
Write-Host "Searching for Custom Deployment Scripts"
$namePrefix = 'DeployTo'
$customEnvironments = @()
Get-Item -Path (Join-Path $ENV:GITHUB_WORKSPACE ".github/$($namePrefix)*.ps1") | ForEach-Object {
    $customEnvironment = [System.IO.Path]::GetFileNameWithoutExtension($_.Name.SubString($namePrefix.Length))
    $customEnvironments += @($customEnvironment)
}

Write-Host "Reading environments from settings"
$settings.excludeEnvironments += @('github_pages')
$environments = @($ghEnvironments | ForEach-Object { $_.name }) + $customEnvironments + @($settings.environments) | Select-Object -unique | Where-Object { $settings.excludeEnvironments -notcontains $_ -and $_ -like $getEnvironments }

Write-Host "Environments found: $($environments -join ', ')"

$deploymentEnvironments = [ordered]@{}

if (!($environments)) {
    # If no environments are defined and the user specified a single environment, use that environment
    # This allows the user to specify a single environment without having to define it in the settings
    if ($getenvironments -notcontains '*' -and $getenvironments -notcontains '?' -and $getenvironments -notcontains ',') {
        $envName = $getEnvironments.Split(' ')[0]
        $deploymentEnvironments += @{
            "$getEnvironments" = @{
                "EnvironmentName" = $envName
                "Branches" = $null
                "BranchesFromPolicy" = $null
                "Projects" = '*'
                "ContinuousDeployment" = !($getEnvironments -like '* (PROD)' -or $getEnvironments -like '* (Production)' -or $getEnvironments -like '* (FAT)' -or $getEnvironments -like '* (Final Acceptance Test)')
                "runs-on" = @($settings."runs-on".Split(',').Trim())
            }
        }
    }
}
else {
    $environments | ForEach-Object {
        $environmentName = $_
        Write-Host "Environment: $environmentName"
        $envName = $_.Split(' ')[0]
        # Default Deployment settings are:
        # - environment name: same
        # - branches: main
        # - projects: all
        # - continuous deployment: only for environments not tagged with PROD or FAT
        # - runs-on: same as settings."runs-on"
        $deploymentSettings = [ordered]@{
            "EnvironmentName" = $envName
            "Branches" = $null
            "BranchesFromPolicy" = $null
            "Projects" = '*'
            "ContinuousDeployment" = $null
            "runs-on" = @($settings."runs-on".Split(',').Trim())
        }

        # Check DeployTo<environmentName> setting
        $settingsName = "DeployTo$envName"
        if ($settings.ContainsKey($settingsName)) {
            # If a DeployTo<environmentName> setting exists - use values from this (over the defaults)
            $deployTo = $settings."$settingsName"
            'EnvironmentName','Branches','Projects','ContinuousDeployment','runs-on' | ForEach-Object {
                if ($deployTo.ContainsKey($_)) {
                    $deploymentSettings."$_" = $deployTo."$_"
                }
            }
        }

        # Get Branch policies on GitHub Environment
        $ghEnvironment = $ghEnvironments | Where-Object { $_.name -eq $environmentName }
        if ($ghEnvironment) {
            # Environment is defined in GitHub - check protection rules
            $headers = GetHeader -token $env:GITHUB_TOKEN
            $branchPolicy = ($ghEnvironment.protection_rules | Where-Object { $_.type -eq "branch_policy" })
            if ($branchPolicy) {
                if ($ghEnvironment.deployment_branch_policy.protected_branches) {
                    Write-Host "GitHub Environment $environmentName only allows protected branches, getting protected branches from GitHub API"
                    $branchesUrl = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/branches"
                    $deploymentSettings.BranchesFromPolicy = @((InvokeWebRequest -Headers $headers -Uri $branchesUrl -ignoreErrors | ConvertFrom-Json) | Where-Object { $_.protected } | ForEach-Object { $_.name })
                }
                elseif ($ghEnvironment.deployment_branch_policy.custom_branch_policies) {
                    Write-Host "GitHub Environment $environmentName has custom deployment branch policies, getting branches from GitHub API"
                    $branchesUrl = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments/$([Uri]::EscapeDataString($environmentName))/deployment-branch-policies"
                    $deploymentSettings.BranchesFromPolicy = @((InvokeWebRequest -Headers $headers -Uri $branchesUrl -ignoreErrors | ConvertFrom-Json).branch_policies | ForEach-Object { $_.name })
                }
            }
            else {
                Write-Host "GitHub Environment $environmentName does not have a branch policy defined"
            }
        }

        # Include Environment if:
        # - Type is not Continous Deployment
        # - Environment is setup for Continuous Deployment (in settings)
        # - Continuous Deployment is unset in settings and environment name doesn't contain PROD or FAT tags
        $includeEnvironment = ($type -ne "CD" -or $deploymentSettings.ContinuousDeployment -or ($deploymentSettings.ContinuousDeployment -eq $null -and !($environmentName -like '* (PROD)' -or $environmentName -like '* (Production)' -or $environmentName -like '* (FAT)' -or $environmentName -like '* (Final Acceptance Test)')))

        # Check branch policies and settings
        if (-not $includeEnvironment) {
            Write-Host "Environment $environmentName is not setup for continuous deployment"
        }
        else {
            # Check whether any GitHub policy disallows this branch to deploy to this environment
            if ($deploymentSettings.BranchesFromPolicy) {
                # Check whether GITHUB_REF_NAME is allowed to deploy to this environment
                $includeEnvironment = $deploymentSettings.BranchesFromPolicy | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }
                if ($deploymentSettings.Branches -and $includeEnvironment) {
                    # Branches are also defined in settings for this environment - only include branches that also exists in settings
                    $includeEnvironment = $deploymentSettings.Branches | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }
                }
            }
            else {
                if ($deploymentSettings.Branches) {
                    # Branches are defined in settings for this environment - only include branches that exists in settings
                    $includeEnvironment = $deploymentSettings.Branches | Where-Object { $ENV:GITHUB_REF_NAME -like $_ }
                }
                else {
                    # If no branch policies are defined in GitHub nor in settings - only allow main branch to deploy
                    $includeEnvironment = $ENV:GITHUB_REF_NAME -eq 'main'
                }
            }
            if (!$includeEnvironment) {
                Write-Host "Environment $environmentName is not setup for deployments from branch $ENV:GITHUB_REF_NAME"
            }
        }
        if ($includeEnvironment) {
            $deploymentEnvironments += @{ "$environmentName" = $deploymentSettings }
            # Dump Deployment settings for included environments
            $deploymentSettings | ConvertTo-Json -Depth 99 | Out-Host
        }
    }
}

# Calculate deployment matrix
$json = [ordered]@{"matrix" = @{ "include" = @() }; "fail-fast" = $false }
$deploymentEnvironments.Keys | ForEach-Object {
    $deploymentEnvironment = $deploymentEnvironments."$_"
    $json.matrix.include += [ordered]@{ "environment" = $_; "os" = "$(ConvertTo-Json -InputObject $deploymentEnvironment."runs-on" -compress)" }
}
$environmentsMatrixJson = $json | ConvertTo-Json -Depth 99 -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "EnvironmentsMatrixJson=$environmentsMatrixJson"
Write-Host "EnvironmentsMatrixJson=$environmentsMatrixJson"

$deploymentEnvironmentsJson = ConvertTo-Json -InputObject $deploymentEnvironments -Depth 99 -Compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DeploymentEnvironmentsJson=$deploymentEnvironmentsJson"
Write-Host "DeploymentEnvironmentsJson=$deploymentEnvironmentsJson"

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "EnvironmentCount=$($deploymentEnvironments.Keys.Count)"
Write-Host "EnvironmentCount=$($deploymentEnvironments.Keys.Count)"
