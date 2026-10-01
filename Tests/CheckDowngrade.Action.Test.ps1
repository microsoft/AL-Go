Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "CheckDowngrade Action Tests" {
    BeforeAll {
        $actionName = "CheckDowngrade"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"
        Invoke-Expression $actionScript
        Import-Module (Join-Path $scriptRoot "..\Deploy\Deploy.psm1" -Resolve) -Force

        function DownloadAndImportBcContainerHelper {}
        function New-BcAuthContext {}
        function Get-BcInstalledExtensions { Param($bcAuthContext, $environment) }
        function Get-AppJsonFromAppFile {}

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'deploymentEnvironmentsJson', Justification = 'False positive.')]
        $deploymentEnvironmentsJson = @{
            "Sandbox" = @{
                "EnvironmentType" = "SaaS"
                "EnvironmentName" = "sandbox-bc"
                "Projects" = "*"
                "buildMode" = "default"
                "excludeAppIds" = @()
                "includeTestAppsInSandboxEnvironment" = $false
                "DependencyInstallMode" = "ignore"
            }
        } | ConvertTo-Json -Depth 10 -Compress
    }

    BeforeEach {
        $env:GITHUB_WORKSPACE = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
        New-Item -Path (Join-Path $env:GITHUB_WORKSPACE '.github') -ItemType Directory -Force | Out-Null
        $env:Secrets = '{"Sandbox-AuthContext":"e30="}'
        $env:Settings = '{}'
        Mock DownloadAndImportBcContainerHelper {}
        Mock New-BcAuthContext { @{ tenantId = 'tenant' } }
        Mock Get-BcInstalledExtensions { @() }
        Mock GetAppsAndDependenciesFromArtifacts { return @('Test.app'), @() }
        Mock Get-AppJsonFromAppFile {
            @{
                id = '00000000-0000-0000-0000-000000000001'
                name = 'Test App'
                version = '1.0.0.0'
            }
        }
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{}
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'Does not initialize dependencies when disabled' {
        CheckDowngrade -environmentName 'Sandbox' -artifactsFolder 'missing' -deploymentEnvironmentsJson $deploymentEnvironmentsJson

        Should -Invoke DownloadAndImportBcContainerHelper -Times 0
    }

    It 'Skips the check when a custom deployment script exists for the environment type' {
        Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeployToSaaS.ps1') -Value '' -Encoding UTF8
        $env:Secrets = '{}'

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Not -Throw
        Should -Invoke DownloadAndImportBcContainerHelper -Times 0
        Should -Invoke New-BcAuthContext -Times 0
        Should -Invoke Get-BcInstalledExtensions -Times 0
    }

    It 'Runs the check when a custom deployment script exists only for another environment type' {
        Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeployToOnPrem.ps1') -Value '' -Encoding UTF8

        CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true

        Should -Invoke Get-BcInstalledExtensions -Times 1
    }

    It 'Skips the check for CD when no AuthContext exists and continuousDeployment is not set' {
        $env:Secrets = '{}'

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Not -Throw
        Should -Invoke New-BcAuthContext -Times 0
        Should -Invoke Get-BcInstalledExtensions -Times 0
    }

    It 'Fails for CD when no AuthContext exists and continuousDeployment is set' {
        $env:Secrets = '{}'
        $env:Settings = @{
            "DeployToSandbox" = @{
                "continuousDeployment" = $true
            }
        } | ConvertTo-Json -Depth 10 -Compress

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Throw "No Authentication Context found*"
    }

    It 'Fails for Publish when no AuthContext exists' {
        $env:Secrets = '{}'

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -type 'Publish' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Throw "No Authentication Context found*"
    }

    It 'Fails when an artifact version is lower than the installed version' {
        Mock Get-BcInstalledExtensions {
            @{
                id = '00000000-0000-0000-0000-000000000001'
                isInstalled = $true
                versionMajor = 2
                versionMinor = 0
                versionBuild = 0
                versionRevision = 0
            }
        }

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Throw "Downgrade check failed:*"
    }

    It 'Passes when the artifact version is not lower than the installed version' {
        Mock Get-AppJsonFromAppFile {
            @{
                id = '00000000-0000-0000-0000-000000000001'
                name = 'Test App'
                version = '2.0.0.0'
            }
        }
        Mock Get-BcInstalledExtensions {
            @{
                id = '00000000-0000-0000-0000-000000000001'
                isInstalled = $true
                versionMajor = 1
                versionMinor = 0
                versionBuild = 0
                versionRevision = 0
            }
        }

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Not -Throw
    }

    It 'Validates only the apps selected for deployment' {
        Mock GetAppsAndDependenciesFromArtifacts { return @(), @('Dependency.app') }
        Mock Get-BcInstalledExtensions {
            @{
                id = '00000000-0000-0000-0000-000000000001'
                isInstalled = $true
                versionMajor = 2
                versionMinor = 0
                versionBuild = 0
                versionRevision = 0
            }
        }

        { CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true } |
            Should -Not -Throw
        Should -Invoke Get-AppJsonFromAppFile -Times 0
    }

    It 'Excludes test apps even when includeTestAppsInSandboxEnvironment is enabled' {
        $env:Settings = @{
            "DeployToSandbox" = @{
                "includeTestAppsInSandboxEnvironment" = $true
            }
        } | ConvertTo-Json -Depth 10 -Compress

        CheckDowngrade -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -failOnAppVersionDowngrade $true

        Should -Invoke GetAppsAndDependenciesFromArtifacts -Times 1 -ParameterFilter {
            $deploymentSettings.includeTestAppsInSandboxEnvironment -eq $false
        }
    }

    It 'Uses resolved DeployTo settings for artifact selection and environment name' {
        $env:Settings = @{
            "DeployToSandbox" = @{
                "EnvironmentName" = "override-bc"
                "Projects" = "ProjectA"
                "buildMode" = "Special"
                "excludeAppIds" = @('00000000-0000-0000-0000-000000000002')
            }
        } | ConvertTo-Json -Depth 10 -Compress

        CheckDowngrade -token 'token' -environmentName 'Sandbox' -artifactsFolder '.artifacts' -deploymentEnvironmentsJson $deploymentEnvironmentsJson -artifactsVersion 'PR_1' -failOnAppVersionDowngrade $true

        Should -Invoke GetAppsAndDependenciesFromArtifacts -Times 1 -ParameterFilter {
            $token -eq 'token' -and
            $artifactsFolder -eq '.artifacts' -and
            $artifactsVersion -eq 'PR_1' -and
            $deploymentSettings.Projects -eq 'ProjectA' -and
            $deploymentSettings.buildMode -eq 'Special' -and
            $deploymentSettings.excludeAppIds -contains '00000000-0000-0000-0000-000000000002'
        }
        Should -Invoke Get-BcInstalledExtensions -Times 1 -ParameterFilter { $environment -eq 'override-bc' }
    }
}
