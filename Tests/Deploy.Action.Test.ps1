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
            Mock PublishPTEApps { $script:publishPTECalled = $true }
            Mock Publish-PerTenantExtensionApps { throw "The action must use the shared AL-Go publisher" }
            Mock Publish-BcContainerApp { }
            Mock UnpublishOldAppVersions { $script:unpublishAfterPublish = $script:publishPTECalled }
            Mock OutputWarning { }
        }

        AfterEach {
            Set-Location $PSScriptRoot
            Remove-Item $env:GITHUB_OUTPUT -Force -ErrorAction SilentlyContinue
            Remove-Item $env:GITHUB_WORKSPACE -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Invokes cleanup after PTE publish when unpublishOldVersions is true' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @(); "unpublishOldVersions" = $true }

            Assert-MockCalled PublishPTEApps -Exactly 1
            Assert-MockCalled UnpublishOldAppVersions -Exactly 1
            $script:unpublishAfterPublish | Should -BeTrue
        }

        It 'Does not invoke cleanup when unpublishOldVersions is not set (default)' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @() }

            Assert-MockCalled PublishPTEApps -Exactly 1
            Assert-MockCalled UnpublishOldAppVersions -Times 0
            Assert-MockCalled OutputWarning -Times 0
        }

        It 'Does not invoke cleanup or warn when unpublishOldVersions is false' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @(); "unpublishOldVersions" = $false }

            Assert-MockCalled PublishPTEApps -Exactly 1
            Assert-MockCalled UnpublishOldAppVersions -Times 0
            Assert-MockCalled OutputWarning -Times 0
        }

        It 'Passes primary apps to the shared publisher using <syncMode>' -TestCases @(
            @{ syncMode = 'Add'; helperSyncMode = 'Add' },
            @{ syncMode = 'ForceSync'; helperSyncMode = 'Force' }
        ) {
            param($syncMode, $helperSyncMode)
            $expectedSyncMode = $helperSyncMode
            Mock PublishPTEApps {
                $PesterBoundParameters.Keys | Should -Not -Contain 'schedule'
            }

            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $syncMode; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @() }

            Assert-MockCalled PublishPTEApps -Exactly 1 -ParameterFilter {
                $environment -eq 'test' -and $bcAuthContext.tenantId -eq 'test-tenant' -and
                $appFiles.Count -eq 1 -and $appFiles[0] -eq '/tmp/app1.app' -and $SchemaSyncMode -eq $expectedSyncMode
            }
            Assert-MockCalled Publish-BcContainerApp -Times 0
            Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
        }

        It 'Does not retry publishing or invoke cleanup after shared publishing fails' {
            Mock PublishPTEApps { throw "Publishing authorization failed" }
            Mock OutputError { param($message) throw $message }

            { InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "PTE"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @(); "unpublishOldVersions" = $true } } | Should -Throw "*Publishing authorization failed*"

            Assert-MockCalled PublishPTEApps -Exactly 1
            Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            Assert-MockCalled Publish-BcContainerApp -Times 0
            Assert-MockCalled UnpublishOldAppVersions -Times 0
        }

        It 'Does not invoke cleanup for Dev scope even when unpublishOldVersions is true' {
            InvokeDeploy -deploymentSettings @{ "EnvironmentType" = "SaaS"; "EnvironmentName" = "test"; "Branches" = @(); "Projects" = "*"; "DependencyInstallMode" = "ignore"; "SyncMode" = $null; "Scope" = "Dev"; "continuousDeployment" = $true; "includeTestAppsInSandboxEnvironment" = $false; "excludeAppIds" = @(); "unpublishOldVersions" = $true }

            Assert-MockCalled Publish-BcContainerApp -Exactly 1
            Assert-MockCalled PublishPTEApps -Times 0
            Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            Assert-MockCalled UnpublishOldAppVersions -Times 0
        }
    }
}
