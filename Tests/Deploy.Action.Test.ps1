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

    It 'Shares custom target and retained native auth through the exact action imports in a fresh host' {
        $repro = Join-Path $TestDrive 'ActionImports.ps1'
        @'
param([string] $actionPath)
$ErrorActionPreference = 'Stop'
$env:GITHUB_WORKSPACE = Split-Path (Split-Path (Split-Path $actionPath))
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($actionPath, [ref]$tokens, [ref]$errors)
$prefix = ($ast.EndBlock.Statements | Select-Object -First 4 | ForEach-Object { $_.Extent.Text }) -join "`n"
$prefix = $prefix.Replace('$PSScriptRoot', "'$(Split-Path $actionPath)'")
$inspection = {
    $expires = [DateTime]::UtcNow.AddHours(1)
    $source = @{ Scopes = 'https://legacy.test/'; AccessToken = 'legacy-token'; UtcExpiresOn = $expires }
    Initialize-AdminCenterAuthContext -authContext $source.Clone() -settings @{
        deploymentBaseUrl = 'https://native.test/root'; deploymentApplicationFamily = 'Custom Family'
    }
    $native = (Get-Command Initialize-AdminCenterAuthContext).Module
    $deploy = Get-Module Deploy
    $nested = & $deploy { (Get-Command Get-AdminCenterInstalledExtensions).Module }
    if (![object]::ReferenceEquals($native, $nested)) { throw 'Action and Deploy must share the native module before any requests.' }
    & $native {
        $script:exchanges = 0
        $script:requests = @()
        function script:Renew-BcAuthContext {
            param($bcAuthContext)
            if ($bcAuthContext.UtcExpiresOn -le [DateTime]::UtcNow) {
                $script:exchanges++
                $bcAuthContext = $bcAuthContext.Clone()
                $bcAuthContext.AccessToken = 'retained-native-token'
                $bcAuthContext.UtcExpiresOn = [DateTime]::UtcNow.AddHours(1)
            }
            return $bcAuthContext
        }
        function script:Invoke-RestMethod {
            param($Uri, $Method, $Headers, $UseBasicParsing, $TimeoutSec, $ErrorAction)
            $script:requests += @{ uri = [string]$Uri; authorization = $Headers.Authorization }
            return @{ value = @() }
        }
        function script:Write-Host { }
    }
    Get-AdminCenterInstalledExtensions -environment Sandbox | Out-Null
    & $deploy {
        param($context)
        GetInstalledExtensions -bcAuthContext $context -environment Sandbox -publishingApi AdminCenter | Out-Null
    } $source
    $state = & $native {
        @{ exchanges = $script:exchanges; requests = $script:requests; scopes = $script:adminCenterAuthContext.Scopes }
    }
    $state.sameInstance = [object]::ReferenceEquals($native, $nested)
    $state.originalUnchanged = $source.Scopes -eq 'https://legacy.test/' -and
        $source.AccessToken -eq 'legacy-token' -and $source.UtcExpiresOn -eq $expires
    $state | ConvertTo-Json -Depth 10 -Compress
}
& ([scriptblock]::Create($prefix + "`n" + $inspection.ToString()))
'@ | Set-Content -Path $repro -Encoding UTF8

        $hostPath = (Get-Process -Id $PID).Path
        $output = & $hostPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $repro -actionPath $scriptPath
        $LASTEXITCODE | Should -Be 0
        $state = $output[-1] | ConvertFrom-Json | ConvertTo-HashTable -recurse
        $state.sameInstance | Should -BeTrue
        $state.originalUnchanged | Should -BeTrue
        $state.exchanges | Should -Be 1
        $state.scopes | Should -Be 'https://native.test/root/'
        $state.requests.Count | Should -Be 2
        foreach ($request in $state.requests) {
            $request.uri | Should -Be 'https://native.test/root/admin/v2.29/applications/Custom%20Family/environments/Sandbox/apps'
            $request.authorization | Should -Be 'Bearer retained-native-token'
        }
    }

    Context "unpublishOldVersions wiring" {
        BeforeAll {
            Import-Module (Join-Path $scriptRoot "Deploy.psm1") -Force
            Import-Module (Join-Path $scriptRoot "..\.Modules\AdminCenterApi.psm1") -DisableNameChecking
            $script:nativeInitializer = Get-Command Initialize-AdminCenterAuthContext -Module AdminCenterApi
            . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1" -Resolve)
            DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

            function InvokeDeploy {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sandbox', Justification = 'Used inside the Invoke-RestMethod mock scriptblock')]
                Param([bool] $sandbox = $true, [hashtable] $deploymentSettings, [hashtable] $repositorySettings = @{}, [hashtable] $authParameters = @{ refreshToken = 'dummy' })
                $json = @{ "test" = $deploymentSettings } | ConvertTo-Json -Depth 10 -Compress
                $authContext = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($authParameters | ConvertTo-Json -Compress)))
                $env:Secrets = @{ "test-AuthContext" = ""; "test_AuthContext" = ""; "AuthContext" = $authContext } | ConvertTo-Json -Compress
                $actionSettings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh" }
                foreach ($name in $repositorySettings.Keys) { $actionSettings[$name] = $repositorySettings[$name] }
                $env:Settings = $actionSettings | ConvertTo-Json -Depth 10 -Compress
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
            Mock Initialize-AdminCenterAuthContext { }
            Mock Initialize-PTEPublishingApi { }
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

        It 'Initializes the PTE route before dependencies and primary publishing' {
            $script:events = @()
            Mock Initialize-AdminCenterAuthContext { $script:events += 'native-auth' }
            Mock Initialize-PTEPublishingApi { $script:events += 'probe' }
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @('/tmp/dependency.app') }
            Mock InstallOrUpgradeApps { $script:events += 'dependency' }
            Mock CheckInstalledApps { $script:events += 'preflight' }
            Mock PublishPTEApps { $script:events += 'primary' }
            Mock UnpublishOldAppVersions {
                $script:events += 'cleanup'
                ($appFiles -join ',') | Should -Be '/tmp/app1.app'
            }

            InvokeDeploy -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'upgrade'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @(); unpublishOldVersions = $true }

            ($script:events -join ',') | Should -Be 'native-auth,probe,dependency,preflight,primary,cleanup'
        }

        It 'Supplies a dedicated native context while preserving BCH consumers in <scope> scope' -TestCases @(
            @{ scope = 'PTE' }, @{ scope = 'Dev' }
        ) {
            param($scope)
            $script:originalAuthContext = @{
                tenantId = 'test-tenant'; Scopes = 'https://legacy.test/'; AccessToken = 'legacy-token'
                UtcExpiresOn = [DateTime]::UtcNow.AddHours(1)
            }
            $originalExpiry = $script:originalAuthContext.UtcExpiresOn
            Mock New-BcAuthContext { return $script:originalAuthContext }
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @('/tmp/dependency.app') }
            Mock Get-AppJsonFromAppFile { return @{ idRanges = @(@{ from = 50000 }) } }
            Mock InstallOrUpgradeApps { }
            Mock Initialize-AdminCenterAuthContext {
                [object]::ReferenceEquals($authContext, $script:originalAuthContext) | Should -BeFalse
                & $script:nativeInitializer -authContext $authContext -settings $settings -preserveScopes:$preserveScopes
                $authContext.Scopes | Should -Be 'https://native.test/'
                $authContext.UtcExpiresOn | Should -Be ([DateTime]::MinValue)
                $authContext.AccessToken = 'native-token'
            }

            InvokeDeploy -repositorySettings @{ deploymentBaseUrl = 'https://native.test' } `
                -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'upgrade'; SyncMode = $null; Scope = $scope; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            Assert-MockCalled New-BcAuthContext -Exactly 1
            Assert-MockCalled Initialize-AdminCenterAuthContext -Exactly 1
            Assert-MockCalled InstallOrUpgradeApps -Exactly 1 -ParameterFilter {
                [object]::ReferenceEquals($bcAuthContext, $script:originalAuthContext)
            }
            if ($scope -eq 'PTE') {
                Assert-MockCalled PublishPTEApps -Exactly 1 -ParameterFilter {
                    [object]::ReferenceEquals($bcAuthContext, $script:originalAuthContext)
                }
            }
            else {
                Assert-MockCalled Publish-BcContainerApp -Exactly 1 -ParameterFilter {
                    [object]::ReferenceEquals($bcAuthContext, $script:originalAuthContext)
                }
            }
            $script:originalAuthContext.Scopes | Should -Be 'https://legacy.test/'
            $script:originalAuthContext.AccessToken | Should -Be 'legacy-token'
            $script:originalAuthContext.UtcExpiresOn | Should -Be $originalExpiry
        }

        It 'Reports invalid native configuration clearly before PTE work in <scope> scope' -TestCases @(
            @{ scope = 'PTE' }, @{ scope = 'Dev' }
        ) {
            param($scope)
            Mock Initialize-AdminCenterAuthContext {
                & $script:nativeInitializer -authContext $authContext -settings $settings -preserveScopes:$preserveScopes
            }
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @('/tmp/dependency.app') }
            Mock Get-AppJsonFromAppFile { return @{ idRanges = @(@{ from = 50000 }) } }
            Mock InstallOrUpgradeApps { }
            Mock OutputError { param($message) throw $message }

            try {
                InvokeDeploy -repositorySettings @{ deploymentBaseUrl = 'http://invalid.test' } `
                    -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'upgrade'; SyncMode = $null; Scope = $scope; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }
                throw 'Expected native configuration validation to fail'
            }
            catch {
                $_.Exception.Message | Should -Match 'deploymentBaseUrl must be an absolute HTTPS API root'
                $_.Exception.Message | Should -Not -Match 'Authentication failed'
            }
            Assert-MockCalled Initialize-PTEPublishingApi -Times 0
            Assert-MockCalled InstallOrUpgradeApps -Times 0
            Assert-MockCalled PublishPTEApps -Times 0
            Assert-MockCalled Publish-BcContainerApp -Times 0
        }

        It 'Does not validate unused native settings for pure Dev deployment' {
            Mock Initialize-AdminCenterAuthContext { throw 'Unused native configuration must not be initialized' }
            Mock OutputError { param($message) throw $message }

            InvokeDeploy -repositorySettings @{ deploymentBaseUrl = 'http://invalid.test'; deploymentApplicationFamily = '' } `
                -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'Dev'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            Assert-MockCalled Initialize-AdminCenterAuthContext -Times 0
            Assert-MockCalled Initialize-PTEPublishingApi -Times 0
            Assert-MockCalled Publish-BcContainerApp -Exactly 1
        }

        It 'Keeps Admin settings separate from BCH authentication, dependencies and cleanup' {
            Mock New-BcAuthContext {
                $script:deploymentConfig = $bcContainerHelperConfig
                $bcContainerHelperConfig.apiBaseUrl | Should -Be 'https://legacy.test'
                return @{ tenantId = 'test-tenant' }
            }
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @('/tmp/dependency.app') }
            Mock Sort-AppFilesByDependencies {
                param($unknownDependencies)
                $unknownDependencies.Value = @('unknown:Dependency_1.0.0.0.app')
            }
            Mock InstallOrUpgradeApps { }
            Mock InstallUnknownDependencies {
                $bcContainerHelperConfig.apiBaseUrl | Should -Be 'https://legacy.test'
            }
            Mock UnpublishOldAppVersions {
                $bcContainerHelperConfig.apiBaseUrl | Should -Be 'https://legacy.test'
            }

            InvokeDeploy -repositorySettings @{
                deploymentBaseUrl = 'https://deploy.test/root/'
                deploymentApplicationFamily = 'Custom / Family'
                apiBaseUrl = 'https://legacy.test'
                baseUrl = 'https://web.test'
            } -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'upgrade'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @(); unpublishOldVersions = $true }

            foreach ($command in @('Initialize-PTEPublishingApi', 'InstallOrUpgradeApps', 'CheckInstalledApps', 'PublishPTEApps')) {
                Assert-MockCalled $command -Exactly 1 -ParameterFilter {
                    !$PesterBoundParameters.ContainsKey('deploymentTarget')
                }
            }
            Assert-MockCalled UnpublishOldAppVersions -Exactly 1
            Assert-MockCalled InstallUnknownDependencies -Exactly 1
            Assert-MockCalled Initialize-AdminCenterAuthContext -Exactly 1 -ParameterFilter {
                $settings.deploymentBaseUrl -eq 'https://deploy.test/root/' -and
                $settings.deploymentApplicationFamily -eq 'Custom / Family' -and !$preserveScopes
            }
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter { $Uri -like 'https://web.test/*' }
            $script:deploymentConfig.apiBaseUrl | Should -Be 'https://legacy.test'
            $script:deploymentConfig.baseUrl | Should -Be 'https://web.test'
        }

        It 'Does not retain the explicit target in a following deployment with only the legacy override' {
            Mock New-BcAuthContext {
                $script:deploymentConfig = $bcContainerHelperConfig
                return @{ tenantId = 'test-tenant' }
            }
            $deployment = @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            InvokeDeploy -deploymentSettings $deployment -repositorySettings @{
                deploymentBaseUrl = 'https://explicit.test'; deploymentApplicationFamily = 'CustomFamily'
                apiBaseUrl = 'https://legacy.test'
            }
            $script:deploymentConfig.apiBaseUrl | Should -Be 'https://legacy.test'
            InvokeDeploy -deploymentSettings $deployment -repositorySettings @{
                apiBaseUrl = 'https://legacy.test'
            }

            Assert-MockCalled PublishPTEApps -Exactly 2
            Assert-MockCalled Initialize-AdminCenterAuthContext -Exactly 1 -ParameterFilter {
                $settings['deploymentBaseUrl'] -eq 'https://explicit.test' -and
                $settings['deploymentApplicationFamily'] -eq 'CustomFamily'
            }
            Assert-MockCalled Initialize-AdminCenterAuthContext -Exactly 1 -ParameterFilter {
                !$settings.ContainsKey('deploymentBaseUrl') -and !$settings.ContainsKey('deploymentApplicationFamily')
            }
            $script:deploymentConfig.apiBaseUrl | Should -Be 'https://legacy.test'
        }

        It 'Does not modify the helper API root when authentication fails' {
            Mock New-BcAuthContext {
                $script:deploymentConfig = $bcContainerHelperConfig
                $bcContainerHelperConfig.apiBaseUrl | Should -Be 'https://legacy.test'
                throw 'Authentication failed'
            }
            Mock OutputError { param($message) throw $message }

            { InvokeDeploy -repositorySettings @{
                deploymentBaseUrl = 'https://explicit.test'
                apiBaseUrl = 'https://legacy.test'
            } -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() } } | Should -Throw '*Authentication failed*'

            $script:deploymentConfig.apiBaseUrl | Should -Be 'https://legacy.test'
            Assert-MockCalled PublishPTEApps -Times 0
            Assert-MockCalled Initialize-PTEPublishingApi -Times 0
            Assert-MockCalled Initialize-AdminCenterAuthContext -Times 0
        }

        It 'Preserves explicitly supplied OAuth scopes instead of silently retargeting their audience' {
            Mock New-BcAuthContext {
                return @{ tenantId = 'tenant'; Scopes = 'https://audience.test/.default' }
            }
            InvokeDeploy -repositorySettings @{ deploymentBaseUrl = 'https://explicit.test' } `
                -authParameters @{ refreshToken = 'dummy'; scopes = @('https://audience.test/.default') } `
                -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            Assert-MockCalled New-BcAuthContext -Exactly 1 -ParameterFilter {
                $scopes -eq 'https://audience.test/.default'
            }
            Assert-MockCalled PublishPTEApps -Exactly 1 -ParameterFilter {
                $bcAuthContext.Scopes -eq 'https://audience.test/.default'
            }
            Assert-MockCalled Initialize-AdminCenterAuthContext -Exactly 1 -ParameterFilter {
                $preserveScopes -and $authContext.Scopes -eq 'https://audience.test/.default' -and
                $settings.deploymentBaseUrl -eq 'https://explicit.test'
            }
        }

        It 'Keeps the original BCH token resource when Admin settings differ' {
            Mock New-BcAuthContext {
                # The action reloads BCH, so mock the current module instance after that import.
                Mock Invoke-RestMethod -ModuleName BcContainerHelper {
                    return @{ access_token = 'fake-token' }
                }
                Mock Parse-JWTtoken -ModuleName BcContainerHelper {
                    return @{ appid = 'fake-client'; exp = 2000000000 }
                }
                $newContext = Get-Command New-BcAuthContext -Module BcContainerHelper
                & $newContext -tenantID 'fake-tenant' -clientID 'fake-client' -clientSecret 'fake-secret' -silent
            }

            InvokeDeploy -repositorySettings @{ deploymentBaseUrl = 'https://explicit.test'; apiBaseUrl = 'https://legacy.test' } `
                -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            Assert-MockCalled Invoke-RestMethod -ModuleName BcContainerHelper -Exactly 1 -ParameterFilter {
                $Uri -eq 'https://login.microsoftonline.com/fake-tenant/oauth2/v2.0/token' -and
                $Body.scope -eq 'https://legacy.test/.default'
            }
        }

        It 'Preserves an explicit resource for native authentication and leaves the BCH context unchanged' {
            $script:originalAuthContext = @{
                tenantId = 'tenant'; Scopes = 'https://explicit-resource.test/'; AccessToken = 'original-token'
            }
            Mock New-BcAuthContext { return $script:originalAuthContext }
            InvokeDeploy -repositorySettings @{ deploymentBaseUrl = 'https://admin.test' } `
                -authParameters @{ refreshToken = 'dummy'; resource = 'https://explicit-resource.test' } `
                -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            Assert-MockCalled PublishPTEApps -Exactly 1 -ParameterFilter {
                $bcAuthContext.Scopes -eq 'https://explicit-resource.test/'
            }
            Assert-MockCalled Initialize-AdminCenterAuthContext -Exactly 1 -ParameterFilter {
                $preserveScopes -and $authContext.Scopes -eq 'https://explicit-resource.test/' -and
                ![object]::ReferenceEquals($authContext, $script:originalAuthContext)
            }
            $script:originalAuthContext.AccessToken | Should -Be 'original-token'
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
            Assert-MockCalled Initialize-PTEPublishingApi -Times 0
        }

        It 'Probes before Dev dependency installation only for PTE dependency packages' -TestCases @(
            @{ from = 50000; expectedProbes = 1 },
            @{ from = 100000; expectedProbes = 0 }
        ) {
            param($from, $expectedProbes)
            $script:dependencyRange = $from
            Mock GetAppsAndDependenciesFromArtifacts { return @('/tmp/app1.app'), @('/tmp/dependency.app') }
            Mock Get-AppJsonFromAppFile { return @{ idRanges = @(@{ from = $script:dependencyRange; to = 999999 }) } }
            $script:events = @()
            Mock Initialize-PTEPublishingApi { $script:events += 'probe' }
            Mock InstallOrUpgradeApps { $script:events += 'dependencies' }

            InvokeDeploy -deploymentSettings @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'upgrade'; SyncMode = $null; Scope = 'Dev'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }

            Assert-MockCalled Initialize-PTEPublishingApi -Exactly $expectedProbes
            Assert-MockCalled PublishPTEApps -Times 0
            Assert-MockCalled Publish-BcContainerApp -Exactly 1
            if ($expectedProbes) { ($script:events -join ',') | Should -Be 'probe,dependencies' }
            else { ($script:events -join ',') | Should -Be 'dependencies' }
        }

        It 'Stops before publishing when authentication or the route probe fails' {
            Mock InstallOrUpgradeApps { }
            $deployment = @{ EnvironmentType = 'SaaS'; EnvironmentName = 'test'; Branches = @(); Projects = '*'; DependencyInstallMode = 'ignore'; SyncMode = $null; Scope = 'PTE'; continuousDeployment = $true; includeTestAppsInSandboxEnvironment = $false; excludeAppIds = @() }
            Mock New-BcAuthContext { throw 'Authentication failed' }
            { InvokeDeploy -deploymentSettings $deployment } | Should -Throw '*Authentication failed*'

            Mock New-BcAuthContext { return @{ tenantId = 'test-tenant' } }
            Mock Initialize-PTEPublishingApi { throw 'Probe timeout' }
            Mock OutputError { param($message) throw $message }
            { InvokeDeploy -deploymentSettings $deployment } | Should -Throw '*Probe timeout*'
            Assert-MockCalled PublishPTEApps -Times 0
            Assert-MockCalled InstallOrUpgradeApps -Times 0
        }
    }
}
