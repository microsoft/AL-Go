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
