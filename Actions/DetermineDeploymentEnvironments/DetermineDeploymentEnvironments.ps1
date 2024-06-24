Param(
    [Parameter(HelpMessage = "Specifies the pattern of the environments you want to retreive (* for all)", Mandatory = $true)]
    [string] $getEnvironments,
    [Parameter(HelpMessage = "Type of deployment (CD, Publish or All)", Mandatory = $true)]
    [ValidateSet('CD','Publish','All')]
    [string] $type
)

function IsGitHubPagesAvailable() {
    $headers = GetHeader -token $env:GITHUB_TOKEN
    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/pages"
    try {
        Write-Host "Requesting GitHub Pages settings from GitHub"
        $ghPages = (InvokeWebRequest -Headers $headers -Uri $url).Content | ConvertFrom-Json
        return ($ghPages.build_type -eq 'workflow')
    }
    catch {
        return $false
    }
}

function GetGitHubEnvironments() {
    $headers = GetHeader -token $env:GITHUB_TOKEN
    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"
    try {
        Write-Host "Requesting environments from GitHub"
        $ghEnvironments = @(((InvokeWebRequest -Headers $headers -Uri $url).Content | ConvertFrom-Json).environments)
    }
    catch {
        $ghEnvironments = @()
        Write-Host "Failed to get environments from GitHub API - Environments are not supported in this repository"
    }
    $ghEnvironments
}

function Get-BranchesFromPolicy($ghEnvironment) {
    if ($ghEnvironment) {
        # Environment is defined in GitHub - check protection rules
        $headers = GetHeader -token $env:GITHUB_TOKEN
        $branchPolicy = ($ghEnvironment.protection_rules | Where-Object { $_.type -eq "branch_policy" })
        if ($branchPolicy) {
            if ($ghEnvironment.deployment_branch_policy.protected_branches) {
                Write-Host "GitHub Environment $($ghEnvironment.name) only allows protected branches, getting protected branches from GitHub API"
                $branchesUrl = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/branches"
                return ((InvokeWebRequest -Headers $headers -Uri $branchesUrl).Content | ConvertFrom-Json) | Where-Object { $_.protected } | ForEach-Object { $_.name }
            }
            elseif ($ghEnvironment.deployment_branch_policy.custom_branch_policies) {
                Write-Host "GitHub Environment $($ghEnvironment.name) has custom deployment branch policies, getting branches from GitHub API"
                $branchesUrl = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments/$([Uri]::EscapeDataString($ghEnvironment.name))/deployment-branch-policies"
                return ((InvokeWebRequest -Headers $headers -Uri $branchesUrl).Content | ConvertFrom-Json).branch_policies | ForEach-Object { $_.name }
            }
        }
        else {
            Write-Host "GitHub Environment $($ghEnvironment.name) does not have a branch policy defined"
        }
    }
}

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable -recurse

$includeGitHubPages = $getEnvironments.Split(',') | Where-Object { 'github-pages' -like $_ }
$generateALDocArtifact = ($includeGitHubPages) -and (($type -eq 'Publish') -or $settings.alDoc.continuousDeployment)
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "GenerateALDocArtifact=$([int]$generateALDocArtifact)"
Write-Host "GenerateALDocArtifact=$([int]$generateALDocArtifact)"

$deployToGitHubPages = $settings.alDoc.DeployToGitHubPages
if ($generateALDocArtifact -and $deployToGitHubPages) {
    $deployToGitHubPages = IsGitHubPagesAvailable
    if (!$deployToGitHubPages) {
        Write-Host "::Warning::GitHub Pages is not available in this repository (or GitHub Pages is not set to use GitHub Actions). Go to Settings -> Pages and set Source to GitHub Actions"
    }
}
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DeployALDocArtifact=$([int]$deployToGitHubPages)"
Write-Host "DeployALDocArtifact=$([int]$deployToGitHubPages)"

if ($getEnvironments -eq 'github-pages') {
    # if github-pages is specified as environment - only include if GitHub Pages is available
    exit 0
}

Write-Host "Environment pattern to use: $getEnvironments"
$ghEnvironments = @(GetGitHubEnvironments)

Write-Host "Reading environments from settings"
$settings.excludeEnvironments += @('github-pages')
$environments = @($ghEnvironments | ForEach-Object { $_.name }) + @($settings.environments) | Select-Object -unique | Where-Object { $settings.excludeEnvironments -notcontains $_.Split(' ')[0] -and $_.Split(' ')[0] -like $getEnvironments }

Write-Host "Environments found: $($environments -join ', ')"

$deploymentEnvironments = @{}
$unknownEnvironment = 0

if (!($environments)) {
    # If no environments are defined and the user specified a single environment, use that environment
    # This allows the user to specify a single environment without having to define it in the settings
    if ($getenvironments -notcontains '*' -and $getenvironments -notcontains '?' -and $getenvironments -notcontains ',') {
        $envName = $getEnvironments.Split(' ')[0]
        $deploymentEnvironments += @{
            "$getEnvironments" = @{
                "EnvironmentType" = "SaaS"
                "EnvironmentName" = $envName
                "Branches" = $null
                "BranchesFromPolicy" = @()
                "Projects" = '*'
                "SyncMode" = $null
                "Scope" = $null
                "continuousDeployment" = !($getEnvironments -like '* (PROD)' -or $getEnvironments -like '* (Production)' -or $getEnvironments -like '* (FAT)' -or $getEnvironments -like '* (Final Acceptance Test)')
                "runs-on" = @($settings."runs-on".Split(',').Trim())
                "shell" = $settings."shell"
                "companyId" = ''
                "ppEnvironmentUrl" = ''
            }
        }
        $unknownEnvironment = 1
    }
}
else {
    foreach($environmentName in $environments) {
        Write-Host "Environment: $environmentName"
        $envName = $environmentName.Split(' ')[0]

        # Check Obsolete Settings
        foreach($obsoleteSetting in "$($envName)-Projects","$($envName)_Projects") {
            if ($settings.Contains($obsoleteSetting)) {
                throw "The setting $obsoleteSetting is obsolete and should be replaced by using the Projects property in the DeployTo$envName setting in .github/AL-Go-Settings.json instead"
            }
        }

        # Default Deployment settings are:
        # - environment name: same
        # - branches: main
        # - projects: all
        # - continuous deployment: only for environments not tagged with PROD or FAT
        # - runs-on: same as settings."runs-on"
        # - shell: same as settings."shell"
        # - no companyId
        # - no ppEnvironmentUrl
        $deploymentSettings = @{
            "EnvironmentType" = "SaaS"
            "EnvironmentName" = $envName
            "Branches" = @()
            "BranchesFromPolicy" = @()
            "Projects" = '*'
            "SyncMode" = $null
            "Scope" = $null
            "continuousDeployment" = $null
            "runs-on" = @($settings."runs-on".Split(',').Trim())
            "shell" = $settings."shell"
            "companyId" = ''
            "ppEnvironmentUrl" = ''
        }

        # Check DeployTo<environmentName> setting
        $settingsName = "DeployTo$envName"
        if ($settings.ContainsKey($settingsName)) {
            # If a DeployTo<environmentName> setting exists - use values from this (over the defaults)
            Write-Host "Setting $settingsName"
            $deployTo = $settings."$settingsName"
            $keys = @($deploymentSettings.Keys)
            foreach($key in $keys) {
                if ($deployTo.ContainsKey($key)) {
                    if ($deploymentSettings."$key".GetType().Name -ne $deployTo."$key".GetType().Name) {
                        Write-Host "::WARNING::The property $key in $settingsName is expected to be of type $($deploymentSettings."$key".GetType().Name)"
                    }
                    Write-Host "Property $key = $($deployTo."$key")"
                    $deploymentSettings."$key" = $deployTo."$key"
                }
                else {
                    $deploymentSettings += @{
                        "$key" = $deployTo."$key"
                    }
                }

            }
            if ($deploymentSettings."shell" -ne 'pwsh' -and $deploymentSettings."shell" -ne 'powershell') {
                throw "The shell setting in $settingsName must be either 'pwsh' or 'powershell'"
            }
        }

        # Get Branch policies on GitHub Environment
        $ghEnvironment = $ghEnvironments | Where-Object { $_.name -eq $environmentName }
        $deploymentSettings.BranchesFromPolicy = @(Get-BranchesFromPolicy -ghEnvironment $ghEnvironment)

        # Include Environment if:
        # - Type is not Continous Deployment
        # - Environment is setup for Continuous Deployment (in settings)
        # - Continuous Deployment is unset in settings and environment name doesn't contain PROD or FAT tags
        switch ($type) {
            'CD' {
                if ($null -eq $deploymentSettings.continuousDeployment) {
                    # Continuous Deployment is unset in settings - only include environments not tagged with PROD or FAT
                    $includeEnvironment = !($environmentName -like '* (PROD)' -or $environmentName -like '* (Production)' -or $environmentName -like '* (FAT)' -or $environmentName -like '* (Final Acceptance Test)')
                }
                else {
                    # Continuous Deployment is set in settings, use this value
                    $includeEnvironment = $deploymentSettings.continuousDeployment
                }
            }
            'Publish' {
                # Publish can publish to all environments
                $includeEnvironment = $true
            }
            'All' {
                $includeEnvironment = $true
            }
            default {
                throw "Unknown type: $type"
            }
        }

        # Check branch policies and settings
        if (-not $includeEnvironment) {
            Write-Host "Environment $environmentName is not setup for continuous deployment"
        }
        elseif ($type -ne 'All') {
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
$json = @{"matrix" = @{ "include" = @() }; "fail-fast" = $false }
$deploymentEnvironments.Keys | Sort-Object | ForEach-Object {
    $deploymentEnvironment = $deploymentEnvironments."$_"
    $json.matrix.include += @{ "environment" = $_; "os" = "$(ConvertTo-Json -InputObject $deploymentEnvironment."runs-on" -compress)"; "shell" = $deploymentEnvironment."shell" }
}
$environmentsMatrixJson = $json | ConvertTo-Json -Depth 99 -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "EnvironmentsMatrixJson=$environmentsMatrixJson"
Write-Host "EnvironmentsMatrixJson=$environmentsMatrixJson"

$deploymentEnvironmentsJson = ConvertTo-Json -InputObject $deploymentEnvironments -Depth 99 -Compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "DeploymentEnvironmentsJson=$deploymentEnvironmentsJson"
Write-Host "DeploymentEnvironmentsJson=$deploymentEnvironmentsJson"

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "EnvironmentCount=$($deploymentEnvironments.Keys.Count)"
Write-Host "EnvironmentCount=$($deploymentEnvironments.Keys.Count)"

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "UnknownEnvironment=$unknownEnvironment"
Write-Host "UnknownEnvironment=$unknownEnvironment"
