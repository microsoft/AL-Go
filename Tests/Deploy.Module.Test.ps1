Import-Module (Join-Path $PSScriptRoot '../Actions/Github-Helper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/DebugLogHelper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/Deploy/Deploy.psm1') -Force

InModuleScope Deploy { # Allows testing of private functions
    Describe "Deploy" {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
            DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

            $script:appSourceApp1Id = "00000000-0000-0000-0000-000000000001"
            $script:pteApp1Id = "00000000-0000-0000-0000-000000000002"
            $script:appSourceAppTestId = "00000000-0000-0000-0000-000000000003"
            $script:devScopeAppId = "00000000-0000-0000-0000-000000000004"
        }

        BeforeEach {
            # Set up common test environment variables
            $env:GITHUB_WORKSPACE = [System.IO.Path]::GetTempPath()
            $env:GITHUB_REPOSITORY = "test/repo"
            $env:GITHUB_REF_NAME = "main"

            # Mock functions from AL-Go-Helper and Github-Helper
            Mock GetHeaders { return @{ "Authorization" = "Bearer test-token" } }
            Mock InvokeWebRequest {
                param($Uri)
                if ($Uri -like "*/pulls/*") {
                    return @{
                        Content = @{
                            head = @{
                                ref = "feature/test-branch"
                            }
                        } | ConvertTo-Json
                    }
                }
                return @{ Content = "{}" }
            }
            Mock OutputDebugFunctionCall { }
            Mock OutputGroupStart { }
            Mock OutputGroupEnd { }
            Mock OutputDebug { }
            Mock OutputWarning { }
            Mock Get-AppJsonFromAppFile {
                param($appFile)
                switch ($appFile) {
                    { $appFile -like "*AppSourceApp.app" } {
                        return @{
                            id = $script:appSourceApp1Id
                            name = "AppSource App"
                            Version = "2.0.0.0"
                            idRanges = @( @{ from = 100000; to = 199999 } )  # AppSource range
                        }
                    }
                    { $appFile -like "*PTEApp.app" } {
                        return @{
                            id = $script:pteApp1Id
                            name = "PTE App"
                            Version = "2.0.0.0"
                            idRanges = @( @{ from = 50000; to = 99999 } )  # PTE range
                        }
                    }
                    { $appFile -like "*AppSourceApp.Test.app" } {
                        return @{
                            id = $script:appSourceAppTestId
                            name = "AppSource App Test"
                            Version = "2.0.0.0"
                            idRanges = @( @{ from = 100000; to = 199999 } )  # AppSource range
                        }
                    }
                    { $appFile -like "*DevScopeApp.app" } {
                        return @{
                            id = $script:devScopeAppId
                            name = "Dev Scope App"
                            Version = "2.0.0.0"
                            idRanges = @( @{ from = 100000; to = 199999 } )  # AppSource range
                        }
                    }
                    Default {
                        return @{
                            id = "12345678-1234-1234-1234-123456789012"
                            name = "Test App"
                            version = "1.0.0.0"
                        }
                    }
                }
            }
            Mock Sort-AppFilesByDependencies { }
            Mock Write-Host { }
        }

        AfterEach {
            Remove-Item -Path $env:GITHUB_WORKSPACE -Recurse -Force -ErrorAction SilentlyContinue
        }

        Describe "GetHeadRefFromPRId" {
            It 'Returns correct head ref from PR API response' {
                $result = GetHeadRefFromPRId -repository "test/repo" -prId "123" -token "test-token"

                $result | Should -Be "feature/test-branch"

                Assert-MockCalled GetHeaders -Exactly 1 -ParameterFilter { $token -eq "test-token" }
                Assert-MockCalled InvokeWebRequest -Exactly 1 -ParameterFilter {
                    $Uri -eq "https://api.github.com/repos/test/repo/pulls/123"
                }
            }

            It 'Calls API with correct parameters' {
                GetHeadRefFromPRId -repository "owner/repo" -prId "456" -token "another-token"

                Assert-MockCalled InvokeWebRequest -Exactly 1 -ParameterFilter {
                    $Uri -eq "https://api.github.com/repos/owner/repo/pulls/456"
                }
            }
        }

        Describe "GetAppsAndDependenciesFromArtifacts" {
            BeforeEach {
                # Create test artifact folder structure
                $artifactsFolder = Join-Path $env:GITHUB_WORKSPACE "artifacts"
                New-Item -Path $artifactsFolder -ItemType Directory -Force | Out-Null

                # Create project artifact folders
                $projectAppsFolder = Join-Path $artifactsFolder "project1-main-Apps-1.0.0.0"
                $projectTestAppsFolder = Join-Path $artifactsFolder "project1-main-TestApps-1.0.0.0"
                $projectDepsFolder = Join-Path $artifactsFolder "project1-main-Dependencies-1.0.0.0"
                $project2AppsFolder = Join-Path $env:GITHUB_WORKSPACE "artifacts/project2-main-Apps-1.0.0.0"

                New-Item -Path $projectAppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path $projectTestAppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path $projectDepsFolder -ItemType Directory -Force | Out-Null            
                New-Item -Path $project2AppsFolder -ItemType Directory -Force | Out-Null              

                # Create test .app files
                New-Item -Path (Join-Path $projectAppsFolder "AppSourceApp.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $projectAppsFolder "PTEApp.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $projectTestAppsFolder "AppSourceApp.Test.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $projectDepsFolder "Dependency.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $project2AppsFolder "Project2App.app") -ItemType File -Force | Out-Null
            }

            It 'Returns apps and dependencies from artifacts folder' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings

                $apps.Count | Should -Be 2
                $apps | Should -Contain (Join-Path $projectAppsFolder "AppSourceApp.app")
                $apps | Should -Contain (Join-Path $projectAppsFolder "PTEApp.app")

                $dependencies.Count | Should -Be 1
                $dependencies | Should -Contain (Join-Path $projectDepsFolder "Dependency.app")
            }

            It 'Includes test apps when includeTestAppsInSandboxEnvironment is true' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $true
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings

                $apps.Count | Should -Be 3
                $apps | Should -Contain (Join-Path $projectTestAppsFolder "AppSourceApp.Test.app")
            }

            It 'Excludes apps with specified IDs' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @($script:appSourceApp1Id)
                    DependencyInstallMode = "install"
                }

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings

                $apps.Count | Should -Be 1
            }

            It 'Ignores dependencies when DependencyInstallMode is ignore' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "ignore"
                }

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings

                $dependencies.Count | Should -Be 0
            }

            It 'Handles multiple projects' {
                $deploymentSettings = @{
                    Projects = "project1,project2"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings

                $apps.Count | Should -Be 3
                $apps | Should -Contain (Join-Path $project2AppsFolder "Project2App.app")
            }

            It 'Throws error when artifacts folder does not exist' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }

                { GetAppsAndDependenciesFromArtifacts -artifactsFolder "nonexistent" -deploymentSettings $deploymentSettings } | Should -Throw "*was not found*"
            }

            It 'Handles PR artifacts correctly' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }

                # Mock PR artifact scenario
                $artifactsVersion = "PR_123"

                # Mock GetHeadRefFromPRId to return a branch name
                Mock GetHeadRefFromPRId { return "feature_test-branch" }

                # Create PR-style artifact folder
                $prAppsFolder = Join-Path $env:GITHUB_WORKSPACE "artifacts/project1-feature_test-branch-Apps-PR123-20230101"
                New-Item -Path $prAppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $prAppsFolder "PRApp.app") -ItemType File -Force | Out-Null

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -token 'token' -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings -artifactsVersion $artifactsVersion

                Assert-MockCalled GetHeadRefFromPRId -Exactly 1
                $apps.Count | Should -Be 1
                $apps | Should -Contain (Join-Path $prAppsFolder "PRApp.app")
            }

            It 'Warns when test apps are requested but not found' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $true
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }

                $artifactsFolder = Join-Path $env:GITHUB_WORKSPACE "artifacts"
                $projectTestAppsFolder = Join-Path $artifactsFolder "project1-main-TestApps-1.0.0.0"
                Remove-Item -Path $projectTestAppsFolder -Recurse -Force -ErrorAction SilentlyContinue

                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings

                Assert-MockCalled OutputWarning -Exactly 1
            }
        }

        Describe "CheckIfAppNeedsInstallOrUpgrade" {
            It 'Returns install needed when app is not installed and installMode is not ignore' {
                $appJson = @{
                    name = "Test App"
                    Version = "1.0.0.0"
                }
                $installedApp = $null
                $installMode = "install"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $true
                $needsUpgrade | Should -Be $false
                Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*is not installed*" }
            }

            It 'Returns no install needed when app is not installed and installMode is ignore' {
                $appJson = @{
                    name = "Test App"
                    Version = "1.0.0.0"
                }
                $installedApp = $null
                $installMode = "ignore"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $false
            }

            It 'Returns upgrade needed when dependency version is higher and installMode is upgrade' {
                $appJson = @{
                    name = "Test App"
                    Version = "2.0.0.0"
                }
                $installedApp = @{
                    versionMajor = 1
                    versionMinor = 0
                    versionBuild = 0
                    versionRevision = 0
                }
                $installMode = "upgrade"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $true
                Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Needs upgrade*" }
            }

            It 'Returns no upgrade needed when dependency version is higher but installMode is not upgrade' {
                $appJson = @{
                    name = "Test App"
                    Version = "2.0.0.0"
                }
                $installedApp = @{
                    versionMajor = 1
                    versionMinor = 0
                    versionBuild = 0
                    versionRevision = 0
                }
                $installMode = "install"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $false
                Assert-MockCalled OutputWarning -ParameterFilter { $message -like "*Set DependencyInstallMode to 'upgrade'*" }
            }

            It 'Returns no action needed when dependency version equals installed version' {
                $appJson = @{
                    name = "Test App"
                    Version = "1.0.0.0"
                }
                $installedApp = @{
                    versionMajor = 1
                    versionMinor = 0
                    versionBuild = 0
                    versionRevision = 0
                }
                $installMode = "upgrade"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $false
                Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*is already installed in version*" }
            }

            It 'Returns no action needed when dependency version is lower than installed version' {
                $appJson = @{
                    name = "Test App"
                    Version = "1.0.0.0"
                }
                $installedApp = @{
                    versionMajor = 2
                    versionMinor = 0
                    versionBuild = 0
                    versionRevision = 0
                }
                $installMode = "upgrade"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $false
                Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*is already installed in version*which is higher than*" }
            }

            It 'Handles complex version numbers correctly' {
                $appJson = @{
                    name = "Test App"
                    Version = "1.2.3.4"
                }
                $installedApp = @{
                    versionMajor = 1
                    versionMinor = 2
                    versionBuild = 3
                    versionRevision = 3
                }
                $installMode = "upgrade"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $true
            }

            It 'Handles edge case where installed app has null version properties' {
                $appJson = @{
                    name = "Test App"
                    Version = "1.0.0.0"
                }
                $installedApp = @{
                    versionMajor = 0
                    versionMinor = 0
                    versionBuild = 0
                    versionRevision = 0
                }
                $installMode = "upgrade"

                $needsInstall, $needsUpgrade = CheckIfAppNeedsInstallOrUpgrade -appJson $appJson -installedApp $installedApp -installMode $installMode

                $needsInstall | Should -Be $false
                $needsUpgrade | Should -Be $true
            }
        }

        Describe "CheckInstalledApps" {
            BeforeAll {
                $script:higherVersionAppId = "00000000-0000-0000-0000-000000000005"
                $script:lowerVersionAppId = "00000000-0000-0000-0000-000000000006"
                $script:sameVersionAppId = "00000000-0000-0000-0000-000000000007"
                $script:notInstalledAppId = "00000000-0000-0000-0000-000000000008"
            }
            BeforeEach {
                # Mock the BcContainerHelper functions
                Mock Get-BcInstalledExtensions {
                    return @(
                        @{
                            id = $script:higherVersionAppId
                            isInstalled = $true
                            versionMajor = 2
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                        },
                        @{
                            id = $script:sameVersionAppId
                            isInstalled = $true
                            versionMajor = 1
                            versionMinor = 5
                            versionBuild = 0
                            versionRevision = 0
                        },
                        @{
                            id = $script:lowerVersionAppId
                            isInstalled = $true
                            versionMajor = 2
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                        }
                    )
                }

                # Mock Get-AppJsonFromAppFile for different scenarios
                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    switch ($appFile) {
                        { $appFile -like "*HigherVersion.app" } {
                            return @{
                                id = $script:higherVersionAppId
                                name = "Higher Version App"
                                Version = "3.0.0.0"
                            }
                        }
                        { $appFile -like "*LowerVersion.app" } {
                            return @{
                                id = $script:lowerVersionAppId
                                name = "Lower Version App" 
                                Version = "1.0.0.0"
                            }
                        }
                        { $appFile -like "*SameVersion.app" } {
                            return @{
                                id = $script:sameVersionAppId
                                name = "Same Version App"
                                Version = "1.5.0.0"
                            }
                        }
                        { $appFile -like "*NotInstalled.app" } {
                            return @{
                                id = $script:notInstalledAppId
                                name = "Not Installed App"
                                Version = "1.0.0.0"
                            }
                        }
                        Default {
                            return @{
                                id = "12345678-1234-1234-1234-123456789012"
                                name = "Default Test App"
                                Version = "1.0.0.0"
                            }
                        }
                    }
                }
            }

            It 'Does not warn when app version matches installed version' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @("SameVersion.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1 -ParameterFilter { 
                    $bcAuthContext.tenantId -eq "test-tenant" -and $environment -eq "test-env"
                }
                Assert-MockCalled Get-AppJsonFromAppFile -Exactly 1 -ParameterFilter {
                    $appFile -eq "SameVersion.app"
                }
                # Should not call Write-Host with warning
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like "*::WARNING::*" }
            }

            It 'Does not warn when app version is higher than installed version' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @("HigherVersion.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Get-AppJsonFromAppFile -Exactly 1 -ParameterFilter {
                    $appFile -eq "HigherVersion.app"
                }
                # Should not call Write-Host with warning for higher version
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like "*::WARNING::*" }
            }

            It 'Warns when app version is lower than installed version' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env" 
                $appFiles = @("LowerVersion.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Get-AppJsonFromAppFile -Exactly 1 -ParameterFilter {
                    $appFile -eq "LowerVersion.app"
                }
                # Should call OutputWarning with warning for lower version
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { 
                    $message -like "*is already installed in version*which is higher than*"
                }
            }

            It 'Does not warn when app is not installed' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @("NotInstalled.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Get-AppJsonFromAppFile -Exactly 1 -ParameterFilter {
                    $appFile -eq "NotInstalled.app"
                }
                # Should not call Write-Host with warning for non-installed app
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like "*::WARNING::*" }
            }

            It 'Handles multiple app files correctly' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @("HigherVersion.app", "LowerVersion.app", "SameVersion.app", "NotInstalled.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Get-AppJsonFromAppFile -Exactly 4
                # Should only warn for the lower version app
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { 
                    $message -like "*Lower Version App*"
                }
            }

            It 'Handles empty app files array' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @()

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1
                Assert-MockCalled Get-AppJsonFromAppFile -Times 0
                Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -like "*::WARNING::*" }
            }

            It 'Handles complex version comparison correctly' {
                # Mock for complex version scenario
                Mock Get-BcInstalledExtensions {
                    return @(
                        @{
                            id = "complex-version-app"
                            isInstalled = $true
                            versionMajor = 1
                            versionMinor = 2
                            versionBuild = 3
                            versionRevision = 4
                        }
                    )
                }

                Mock Get-AppJsonFromAppFile {
                    return @{
                        id = "complex-version-app"
                        name = "Complex Version App"
                        Version = "1.2.3.2"  # Lower revision number
                    }
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @("ComplexVersion.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                # Should warn because 1.2.3.2 < 1.2.3.4
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { 
                    $message -like "*1.2.3.4*" -and $message -like "*1.2.3.2*"
                }
            }

            It 'Only considers installed extensions' {
                # Mock to return mix of installed and non-installed extensions
                Mock Get-BcInstalledExtensions {
                    return @(
                        @{
                            id = "00000000-0000-0000-0000-000000000001"
                            isInstalled = $true
                            versionMajor = 2
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                        },
                        @{
                            id = "00000000-0000-0000-0000-000000000002"
                            isInstalled = $false  # Not installed
                            versionMajor = 3
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                        }
                    )
                }

                Mock Get-AppJsonFromAppFile {
                    param($appFile)
                    if ($appFile -like "*App2*") {
                        return @{
                            id = "00000000-0000-0000-0000-000000000002"
                            name = "App 2"
                            Version = "1.0.0.0"
                        }
                    }
                    return @{
                        id = "00000000-0000-0000-0000-000000000001"
                        name = "App 1"
                        Version = "1.0.0.0"
                    }
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $appFiles = @("App1.app", "App2.app")

                CheckInstalledApps -bcAuthContext $bcAuthContext -environment $environment -appFiles $appFiles

                # Should only warn for App1 (which is installed), not App2 (which is not installed)
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { 
                    $message -like "*App 1*"
                }
                Assert-MockCalled OutputWarning -Times 0 -ParameterFilter { 
                    $message -like "*App 2*"
                }
            }
        }

        Describe "InstallOrUpgradeApps" {
            BeforeEach {
                # Mock all BcContainerHelper functions
                Mock Get-BcInstalledExtensions {
                    return @(
                        @{
                            id = $script:appSourceApp1Id
                            isInstalled = $true
                            versionMajor = 1
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                            publishedAs = "Global"
                        },
                        @{
                            id = $script:pteApp1Id
                            isInstalled = $true
                            versionMajor = 1
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                            publishedAs = "Tenant"
                        },
                        @{
                            id = $script:devScopeAppId
                            isInstalled = $true
                            versionMajor = 1
                            versionMinor = 0
                            versionBuild = 0
                            versionRevision = 0
                            publishedAs = "Dev"
                        }
                    )
                }

                Mock Copy-AppFilesToFolder { }

                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "AppSourceApp.app" },
                        @{ FullName = Join-Path $Path "PTEApp.app" }
                    )
                }

                Mock Install-BcAppFromAppSource { 
                    param($bcAuthContext, $environment, $appId, $acceptIsvEula, $installOrUpdateNeededDependencies, $allowInstallationOnProduction)
                    # Mock successful installation
                    return $true
                }

                Mock Publish-PerTenantExtensionApps {
                    param($bcAuthContext, $environment, $appFiles, $SchemaSyncMode)
                    # Mock successful publishing
                    return $true
                }

                Mock New-Item { }
                Mock Remove-Item { }
                Mock Join-Path { 
                    param($Path, $ChildPath)
                    return "$Path\$ChildPath"
                }
            }

            It 'Creates and cleans up temporary directory' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "AppSourceApp.app" }
                    )        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app")
                $installMode = "install"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled New-Item -Exactly 1 -ParameterFilter { 
                    $ItemType -eq "Directory" -and $Path -like "*temp*"
                }
                Assert-MockCalled Remove-Item -Exactly 1 -ParameterFilter { 
                    $Path -like "*temp*" -and $Force -eq $true -and $Recurse -eq $true
                }
            }

            It 'Copies app files to temporary folder' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app", "PTEApp.app")
                $installMode = "install"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Copy-AppFilesToFolder -Exactly 1 -ParameterFilter {
                    $appFiles.Count -eq 2 -and $appFiles -contains "AppSourceApp.app" -and $appFiles -contains "PTEApp.app"
                }
            }

            It 'Gets installed extensions from environment' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "AppSourceApp.app" }
                    )        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app")
                $installMode = "install"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Get-BcInstalledExtensions -Exactly 1 -ParameterFilter {
                    $bcAuthContext.tenantId -eq "test-tenant" -and $environment -eq "test-env"
                }
            }

            It 'Installs AppSource apps via AppSource when upgrade needed' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "AppSourceApp.app" }
                    )        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app")
                $installMode = "upgrade"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Install-BcAppFromAppSource -Exactly 1 -ParameterFilter {
                    $appId -eq $script:appSourceApp1Id -and $acceptIsvEula -eq $true -and $installOrUpdateNeededDependencies -eq $true
                }
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Publishes PTE apps when upgrade needed' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "PTEApp.app" }
                    )        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("PTEApp.app")
                $installMode = "upgrade"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Install-BcAppFromAppSource -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $appFiles.Count -eq 1 -and $SchemaSyncMode -eq "Add"
                }
            }

            It 'Uses Force schema sync mode when installMode is ForceUpgrade' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "PTEApp.app" }
                    )        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("PTEApp.app")
                $installMode = "ForceUpgrade"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $SchemaSyncMode -eq "Force"
                }
            }

            It 'Skips AppSource apps published in Dev scope when upgrade needed' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @(
                        @{ FullName = Join-Path $Path "DevScopeApp.app" }
                    )        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("DevScopeApp.app")
                $installMode = "upgrade"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                # Should not install AppSource app when it's Dev scoped
                Assert-MockCalled Install-BcAppFromAppSource -Times 0
                Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter {
                    $message -like "*is published in Dev scope*"
                }
            }

            It 'Handles mixed AppSource and PTE apps correctly' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app", "PTEApp.app")
                $installMode = "upgrade"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                # Should install AppSource app via AppSource
                Assert-MockCalled Install-BcAppFromAppSource -Exactly 1 -ParameterFilter {
                    $appId -eq $script:appSourceApp1Id
                }
                # Should publish PTE apps
                Assert-MockCalled Publish-PerTenantExtensionApps -Exactly 1 -ParameterFilter {
                    $appFiles.Count -eq 1
                }
            }

            It 'Does nothing when no apps need install or upgrade' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app", "PTEApp.app")
                $installMode = "install"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Install-BcAppFromAppSource -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Handles empty apps array' {
                Mock Get-ChildItem {
                    param($Path, $Filter)
                    return @()        
                }

                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @()
                $installMode = "install"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                Assert-MockCalled Copy-AppFilesToFolder -Exactly 1 -ParameterFilter {
                    $appFiles.Count -eq 0
                }
                Assert-MockCalled Install-BcAppFromAppSource -Times 0
                Assert-MockCalled Publish-PerTenantExtensionApps -Times 0
            }

            It 'Refreshes installed apps list after AppSource installation' {
                $bcAuthContext = @{ tenantId = "test-tenant" }
                $environment = "test-env"
                $apps = @("AppSourceApp.app")
                $installMode = "upgrade"

                InstallOrUpgradeApps -bcAuthContext $bcAuthContext -environment $environment -apps $apps -installMode $installMode

                # Should call Get-BcInstalledExtensions twice: once initially, once after AppSource install
                Assert-MockCalled Get-BcInstalledExtensions -Exactly 2
            }
        }
    }
}
