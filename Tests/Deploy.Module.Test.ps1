Import-Module (Join-Path $PSScriptRoot '../Actions/Github-Helper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/DebugLogHelper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/Deploy/Deploy.psm1') -Force

InModuleScope Deploy { # Allows testing of private functions
    Describe "Deploy" {
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
            # Mock OutputDebug { }
            Mock OutputWarning { }
            Mock Get-AppJsonFromAppFile { 
                return @{
                    id = "12345678-1234-1234-1234-123456789012"
                    name = "Test App"
                    version = "1.0.0.0"
                }
            }
            Mock Sort-AppFilesByDependencies { }
            Mock Write-Host { }
            
            # Mock global variables
            $global:TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"
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
                
                New-Item -Path $projectAppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path $projectTestAppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path $projectDepsFolder -ItemType Directory -Force | Out-Null
                
                # Create test .app files
                New-Item -Path (Join-Path $projectAppsFolder "TestApp1.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $projectAppsFolder "TestApp2.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $projectTestAppsFolder "TestApp.Test.app") -ItemType File -Force | Out-Null
                New-Item -Path (Join-Path $projectDepsFolder "Dependency.app") -ItemType File -Force | Out-Null
            }

            It 'Returns apps and dependencies from artifacts folder' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "install"
                }
                
                # Mock buildMode variable
                $script:buildMode = ""
                
                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings
                
                $apps.Count | Should -Be 2
                $apps | Should -Contain (Join-Path $projectAppsFolder "TestApp1.app")
                $apps | Should -Contain (Join-Path $projectAppsFolder "TestApp2.app")
                
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
                
                $script:buildMode = ""
                
                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings
                
                $apps.Count | Should -Be 3
                $apps | Should -Contain (Join-Path $projectTestAppsFolder "TestApp.Test.app")
            }

            It 'Excludes apps with specified IDs' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @("12345678-1234-1234-1234-123456789012")
                    DependencyInstallMode = "install"
                }
                
                $script:buildMode = ""
                
                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings
                
                $apps.Count | Should -Be 0
            }

            It 'Ignores dependencies when DependencyInstallMode is ignore' {
                $deploymentSettings = @{
                    Projects = "project1"
                    includeTestAppsInSandboxEnvironment = $false
                    excludeAppIds = @()
                    DependencyInstallMode = "ignore"
                }
                
                $script:buildMode = ""
                
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
                
                # Create second project folder
                $project2AppsFolder = Join-Path $env:GITHUB_WORKSPACE "artifacts/project2-main-Apps-1.0.0.0"
                New-Item -Path $project2AppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $project2AppsFolder "Project2App.app") -ItemType File -Force | Out-Null
                
                $script:buildMode = ""
                
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
                $token = "placeholder"
                # $script:buildMode = ""
                
                # Mock GetHeadRefFromPRId to return a branch name
                Mock GetHeadRefFromPRId { return "feature_test-branch" }
                
                # Create PR-style artifact folder
                $prAppsFolder = Join-Path $env:GITHUB_WORKSPACE "artifacts/project1-feature_test-branch-Apps-PR123-20230101"
                New-Item -Path $prAppsFolder -ItemType Directory -Force | Out-Null
                New-Item -Path (Join-Path $prAppsFolder "PRApp.app") -ItemType File -Force | Out-Null
                
                $apps, $dependencies = GetAppsAndDependenciesFromArtifacts -token $token -artifactsFolder "artifacts" -deploymentSettings $deploymentSettings -artifactsVersion $artifactsVersion
                
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
    }
}