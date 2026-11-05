Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Deploy Action Tests" {
    BeforeAll {
        $actionName = "Deploy"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "environmentUrl" = "The URL of the deployed environment"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    Context "unpublishOldVersions wiring" {
        BeforeAll {
            Import-Module (Join-Path $scriptRoot "Deploy.psm1") -Force
            . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1" -Resolve)
            DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

            function InvokeDeploy {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sandbox', Justification = 'Used inside the Invoke-RestMethod mock scriptblock')]
                Param([bool] $sandbox = $true, [hashtable] $deploymentSettings)
                $json = @{ "test" = $deploymentSettings } | ConvertTo-Json -Depth 10 -Compress
                $authContext = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"refreshToken":"dummy"}'))
                $env:Secrets = @{ "test-AuthContext" = ""; "test_AuthContext" = ""; "AuthContext" = $authContext } | ConvertTo-Json -Compress
                $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" } | ConvertTo-Json -Compress
                Mock Invoke-RestMethod { return @{ "Status" = "Ready"; "environmentType" = (@{ $true = 1; $false = 0 }[$sandbox]) } }
                . $scriptPath -token 'dummy' -environmentName 'test' -artifactsFolder 'artifacts' -type 'CD' -deploymentEnvironmentsJson $json
            }
        }

        BeforeEach {
            $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
            $env:GITHUB_WORKSPACE = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
            New-Item -Path $env:GITHUB_WORKSPACE -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $env:GITHUB_WORKSPACE '.github') -ItemType Directory | Out-Null

            $script:publishPTECalled = $false
            $script:unpublishAfterPublish = $false

            Mock New-BcAuthContext { return @{ "tenantId" = "test-tenant" } }
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @() }
            Mock Sort-AppFilesByDependencies { }
            Mock CheckInstalledApps { }
            Mock Publish-PerTenantExtensionApps { $script:publishPTECalled = $true }
            Mock Publish-BcContainerApp { }
            Mock UnpublishOldAppVersions { $script:unpublishAfterPublish = $script:publishPTECalled }
        }

        AfterEach {
            Set-Location $PSScriptRoot
            Remove-Item $env:GITHUB_OUTPUT -Force -ErrorAction SilentlyContinue
            Remove-Item $env:GITHUB_WORKSPACE -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Invokes cleanup after PTE publish when unpublishOldVersions is true' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @(); "unpublishOldVersions" = $true }

            Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
            Assert-MockCalled UnpublishOldAppVersions -Exactly 1
            $script:unpublishAfterPublish | Should -BeTrue
        }

        It 'Does not invoke cleanup when unpublishOldVersions is not set (default)' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @() }

            Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
            Assert-MockCalled UnpublishOldAppVersions -Times 0
        }

        It 'Does not invoke cleanup for Dev scope even when unpublishOldVersions is true' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "Dev"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @(); "unpublishOldVersions" = $true }

            Assert-MockCalled Publish-BcContainerApp -Exactly 1
            Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            Assert-MockCalled UnpublishOldAppVersions -Times 0
        }
    }

    Context "failOnAppVersionDowngrade wiring" {
        BeforeAll {
            Import-Module (Join-Path $scriptRoot "Deploy.psm1") -Force
            . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1" -Resolve)
            DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

            function InvokeDeploy {
                Param([string] $scope, [hashtable] $settings = @{})
                $deploymentSettings = @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = $scope; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @() }
                $json = @{ "test" = $deploymentSettings } | ConvertTo-Json -Depth 10 -Compress
                $authContext = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"refreshToken":"dummy"}'))
                $env:Secrets = @{ "test-AuthContext" = ""; "test_AuthContext" = ""; "AuthContext" = $authContext } | ConvertTo-Json -Compress
                $env:Settings = (@{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" } + $settings) | ConvertTo-Json -Depth 10 -Compress
                Mock Invoke-RestMethod { return @{ "Status" = "Ready"; "environmentType" = 1 } }
                . $scriptPath -token 'dummy' -environmentName 'test' -artifactsFolder 'artifacts' -type 'CD' -deploymentEnvironmentsJson $json
            }
        }

        BeforeEach {
            $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
            $env:GITHUB_WORKSPACE = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
            New-Item -Path $env:GITHUB_WORKSPACE -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $env:GITHUB_WORKSPACE '.github') -ItemType Directory | Out-Null

            $script:checkBeforePublish = $false
            $script:publishCalled = $false

            Mock New-BcAuthContext { return @{ "tenantId" = "test-tenant" } }
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @() }
            Mock Sort-AppFilesByDependencies { }
            Mock CheckInstalledApps { $script:checkBeforePublish = -not $script:publishCalled }
            Mock Publish-PerTenantExtensionApps { $script:publishCalled = $true }
            Mock Publish-BcContainerApp { $script:publishCalled = $true }
            Mock UnpublishOldAppVersions { }
        }

        AfterEach {
            Set-Location $PSScriptRoot
            Remove-Item $env:GITHUB_OUTPUT -Force -ErrorAction SilentlyContinue
            Remove-Item $env:GITHUB_WORKSPACE -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Enforces the downgrade check before publishing with PTE scope' {
            InvokeDeploy -scope 'PTE' -settings @{ "failOnAppVersionDowngrade" = $true }

            Assert-MockCalled CheckInstalledApps -Exactly 1 -ParameterFilter { $failOnDowngrade -eq $true }
            Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1
            $script:checkBeforePublish | Should -BeTrue
        }

        It 'Enforces the downgrade check before publishing with Dev scope' {
            InvokeDeploy -scope 'Dev' -settings @{ "failOnAppVersionDowngrade" = $true }

            Assert-MockCalled CheckInstalledApps -Exactly 1 -ParameterFilter { $failOnDowngrade -eq $true }
            Assert-MockCalled Publish-BcContainerApp -Exactly 1
            $script:checkBeforePublish | Should -BeTrue
        }

        It 'Only warns with PTE scope when failOnAppVersionDowngrade is not set' {
            InvokeDeploy -scope 'PTE'

            Assert-MockCalled CheckInstalledApps -Exactly 1 -ParameterFilter { -not $failOnDowngrade }
        }

        It 'Does not check installed apps with Dev scope when failOnAppVersionDowngrade is not set' {
            InvokeDeploy -scope 'Dev'

            Assert-MockCalled CheckInstalledApps -Times 0
            Assert-MockCalled Publish-BcContainerApp -Exactly 1
        }

        It 'Uses environment-specific failOnAppVersionDowngrade over the global setting' {
            InvokeDeploy -scope 'Dev' -settings @{ "failOnAppVersionDowngrade" = $false; "DeployTotest" = @{ "failOnAppVersionDowngrade" = $true } }

            Assert-MockCalled CheckInstalledApps -Exactly 1 -ParameterFilter { $failOnDowngrade -eq $true }
        }

        It 'Does not publish when the downgrade check fails' {
            Mock CheckInstalledApps { throw "Downgrade check failed" }
            Mock OutputError { }

            InvokeDeploy -scope 'PTE' -settings @{ "failOnAppVersionDowngrade" = $true }

            Assert-MockCalled OutputError -Exactly 1 -ParameterFilter { $message -like "*Downgrade check failed*" }
            Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
        }
    }
}
