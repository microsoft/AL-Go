[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test-only credential')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

# Stub for the BcContainerHelper function so it can be mocked within the module scope
function Get-AppJsonFromAppFile { param($appFile) }
function Get-BcContainerEventLog { param($containerName, [switch] $doNotOpen) }
function AnalyzeRepo { param($settings, $baseFolder, $project, [switch] $doNotCheckArtifactSetting) }

Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/RunTests.psm1' -Resolve) -DisableNameChecking -Force

Describe 'RunTests.psm1 Tests' {
    BeforeAll {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'testCredential', Justification = 'Used in tests')]
        $testCredential = New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "password" -AsPlainText -Force))
        $script:compiledAppMetadataByPath = @{}
        $script:testFoldersByProject = @{}

        function New-TestProject {
            Param(
                [string[]] $CompiledTestApps = @(),
                [hashtable] $CompiledAppIds = @{}
            )
            $projectPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
            $testAppsFolder = Join-Path (Join-Path $projectPath ".buildartifacts") "TestApps"
            New-Item -Path $testAppsFolder -ItemType Directory -Force | Out-Null
            $testFolders = @()
            $index = 0
            foreach ($app in $CompiledTestApps) {
                $index++
                $appPath = Join-Path $testAppsFolder $app
                New-Item -Path $appPath -ItemType File -Force | Out-Null
                $appId = if ($CompiledAppIds.ContainsKey($app)) { "$($CompiledAppIds[$app])" } else { [Guid]::NewGuid().ToString() }
                $appName = [System.IO.Path]::GetFileNameWithoutExtension($app)
                $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($appPath)] = [PSCustomObject]@{
                    id   = $appId
                    name = $appName
                }

                $testFolder = "TestApp$index"
                $testFolderPath = Join-Path $projectPath $testFolder
                New-Item -Path $testFolderPath -ItemType Directory -Force | Out-Null
                @{ id = $appId; name = $appName } | ConvertTo-Json |
                    Set-Content -Path (Join-Path $testFolderPath "app.json") -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $testFolderPath "$appName.al") `
                    -Value "codeunit 50100 TestSource { Subtype = Test; }" -Encoding UTF8
                $testFolders += $testFolder
            }
            $script:testFoldersByProject[$projectPath] = @($testFolders)
            return $projectPath
        }

        function Get-TestFoldersForProject {
            Param(
                [string] $ProjectPath
            )

            return @($script:testFoldersByProject[$ProjectPath])
        }
    }

    BeforeEach {
        $script:eventLogSource = Join-Path $TestDrive "$([Guid]::NewGuid()).evtx"
        Set-Content -Path $script:eventLogSource -Value 'post-test-events' -Encoding UTF8
        Mock -ModuleName RunTests Get-AppJsonFromAppFile {
            $fullPath = [System.IO.Path]::GetFullPath("$appFile")
            if (-not $script:compiledAppMetadataByPath.ContainsKey($fullPath)) {
                throw "No test metadata configured for '$appFile'."
            }
            return $script:compiledAppMetadataByPath[$fullPath]
        }
        Mock -ModuleName RunTests Get-BcContainerEventLog { return $script:eventLogSource }
    }

    It 'Delegates coverage lifecycle ownership to the coordinator module' {
        $moduleText = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot '../Actions/RunTests/RunTests.psm1'
        ) -Raw -Encoding UTF8

        $moduleText | Should -Match "CodeCoverageCoordinator\.psm1"
        $moduleText | Should -Match 'New-AlGoCodeCoverageSession'
        $moduleText | Should -Match 'Complete-AlGoCodeCoverageSession'
        $moduleText | Should -Not -Match 'Write-CodeCoverageStatus'
    }

    Context 'Get-TestAppsToRun' {
        It 'Collects compiled test apps from the build artifacts folder' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath)

            $testApps.Count | Should -Be 2
            $testApps | ForEach-Object { $_ | Should -BeOfType System.Management.Automation.PSCustomObject }
            @($testApps.Path | ForEach-Object { [System.IO.Path]::GetFileName($_) }) |
                Should -Be @('App1.Test.app', 'App2.Test.app')
            @($testApps.Name) | Should -Be @('App1.Test', 'App2.Test')
            @($testApps.Id) | Should -Be @(
                "$($script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($testApps[0].Path)].id)",
                "$($script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($testApps[1].Path)].id)"
            )
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Includes installed test apps (unwrapping parentheses) when runTestsInAllInstalledTestApps is set' {
            $projectPath = New-TestProject
            $installedApp1 = Join-Path $projectPath 'Installed1.app'
            $installedApp2 = Join-Path $projectPath 'Installed2.app'
            New-Item -Path $installedApp1 -ItemType File -Force | Out-Null
            New-Item -Path $installedApp2 -ItemType File -Force | Out-Null
            $installedApp1Id = [Guid]::NewGuid().ToString()
            $installedApp2Id = [Guid]::NewGuid().ToString()
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($installedApp1)] = [PSCustomObject]@{
                id = $installedApp1Id; name = 'Installed1'
            }
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($installedApp2)] = [PSCustomObject]@{
                id = $installedApp2Id; name = 'Installed2'
            }
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @($installedApp1, "($installedApp2)") | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{ runTestsInAllInstalledTestApps = $true; testFolders = @() }
            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson)

            $testApps.Count | Should -Be 2
            @($testApps.Path) | Should -Be @($installedApp1, $installedApp2)
            @($testApps.Id) | Should -Be @($installedApp1Id, $installedApp2Id)
            @($testApps.Name) | Should -Be @('Installed1', 'Installed2')
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Includes unwrapped installed apps and skips parenthesized apps when runTestsInAllInstalledTestApps is not set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $installedApp1 = Join-Path $projectPath 'Installed1.app'
            $installedApp2 = Join-Path $projectPath 'Installed2.app'
            New-Item -Path $installedApp1 -ItemType File -Force | Out-Null
            New-Item -Path $installedApp2 -ItemType File -Force | Out-Null
            $installedApp1Id = [Guid]::NewGuid().ToString()
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($installedApp1)] = [PSCustomObject]@{
                id = $installedApp1Id; name = 'Installed1'
            }
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($installedApp2)] = [PSCustomObject]@{
                id = [Guid]::NewGuid().ToString(); name = 'Installed2'
            }
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @($installedApp1, "($installedApp2)") | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }
            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson)

            $testApps.Count | Should -Be 2
            [System.IO.Path]::GetFileName($testApps[0].Path) | Should -Be 'App1.Test.app'
            $testApps[1].Path | Should -Be $installedApp1
            $testApps[1].Id | Should -Be $installedApp1Id
            $testApps[1].Name | Should -Be 'Installed1'
            @($testApps.Path) | Should -Not -Contain $installedApp2
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not throw and returns compiled test apps when installTestAppsJson is an empty array' {
            # Regression: in Windows PowerShell 5.1 ConvertFrom-Json emits a JSON array as a single
            # object, so an empty '[]' previously surfaced as a one-element System.Object[] and threw
            # "does not contain a method named 'TrimStart'". A test project with no installed test apps
            # (the common case) must still return its compiled test apps without throwing.
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @() | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{
                runTestsInAllInstalledTestApps = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }
            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson)

            $testApps.Count | Should -Be 1
            [System.IO.Path]::GetFileName($testApps[0].Path) | Should -Be 'App1.Test.app'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Includes a single installed test app when runTestsInAllInstalledTestApps is set' {
            # Regression: a single-element JSON array must enumerate to the string element (not the
            # whole array) on both Windows PowerShell 5.1 and PowerShell 7.
            $projectPath = New-TestProject
            $installedApp = Join-Path $projectPath 'Installed1.app'
            New-Item -Path $installedApp -ItemType File -Force | Out-Null
            $installedAppId = [Guid]::NewGuid().ToString()
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($installedApp)] = [PSCustomObject]@{
                id = $installedAppId; name = 'Installed1'
            }
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @("($installedApp)") | Set-Content -Path $installJson -Encoding UTF8

            $settings = @{ runTestsInAllInstalledTestApps = $true; testFolders = @() }
            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson)

            $testApps.Count | Should -Be 1
            $testApps[0].Path | Should -Be $installedApp
            $testApps[0].Id | Should -Be $installedAppId
            $testApps[0].Name | Should -Be 'Installed1'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Fails when an installed test app listed by RunPipeline is missing' {
            $projectPath = New-TestProject
            $missingApp = Join-Path $projectPath 'Missing.Test.app'
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @($missingApp) | Set-Content -Path $installJson -Encoding UTF8
            $settings = @{ runTestsInAllInstalledTestApps = $true; testFolders = @() }

            { Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson } |
                Should -Throw "*Failed to read installed test app metadata*$missingApp*"

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Reports malformed installed test app JSON with handoff context' {
            $projectPath = New-TestProject
            $installJson = Join-Path $projectPath 'installTestApps.json'
            Set-Content -Path $installJson -Value '{invalid' -Encoding UTF8
            $settings = @{ runTestsInAllInstalledTestApps = $false; testFolders = @() }

            {
                Get-TestAppsToRun -settings $settings -projectPath $projectPath `
                    -installTestAppsJson $installJson
            } | Should -Throw "*Failed to parse JSON file*$installJson*"

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Selects an app ID only once when compiled and installed paths differ' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $compiledAppPath = Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'TestApps') 'App1.Test.app'
            $installedAppPath = Join-Path $projectPath 'InstalledCopy.app'
            New-Item -Path $installedAppPath -ItemType File -Force | Out-Null
            $compiledAppId = "$($script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($compiledAppPath)].id)"
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($installedAppPath)] = [PSCustomObject]@{
                id = $compiledAppId; name = 'Installed Copy'
            }
            $installJson = Join-Path $projectPath 'installTestApps.json'
            ConvertTo-Json @($installedAppPath) | Set-Content -Path $installJson -Encoding UTF8
            $settings = @{
                runTestsInAllInstalledTestApps = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath -installTestAppsJson $installJson)

            $testApps.Count | Should -Be 1
            $testApps[0].Path | Should -Be $compiledAppPath
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Selects only compiled apps whose IDs belong to normal test folders' {
            $projectPath = New-TestProject -CompiledTestApps @('Normal.Test.app', 'Performance.Test.app')
            $testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @($testFolders[0])
                bcptTestFolders                = @($testFolders[1])
            }

            $testApps = @(Get-TestAppsToRun -settings $settings -projectPath $projectPath)

            $testApps.Count | Should -Be 1
            [System.IO.Path]::GetFileName($testApps[0].Path) | Should -Be 'Normal.Test.app'
            $testApps[0].Name | Should -Be 'Normal.Test'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Reports corrupt normal source app metadata clearly' {
            $projectPath = New-TestProject
            $testFolder = Join-Path $projectPath 'BrokenTestApp'
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $testFolder 'app.json') -Value '{invalid' -Encoding UTF8
            $settings = @{ runTestsInAllInstalledTestApps = $false; testFolders = @('BrokenTestApp') }

            { Get-TestAppsToRun -settings $settings -projectPath $projectPath } |
                Should -Throw "*Failed to read normal test app metadata*BrokenTestApp*app.json*"

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Reports unreadable compiled app metadata clearly' {
            $projectPath = New-TestProject -CompiledTestApps @('Broken.Test.app')
            Mock -ModuleName RunTests Get-AppJsonFromAppFile { throw 'corrupt package' }
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Get-TestAppsToRun -settings $settings -projectPath $projectPath } |
                Should -Throw "*Failed to read compiled test app metadata*Broken.Test.app*corrupt package*"

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Reports invalid selected compiled app metadata clearly' {
            $projectPath = New-TestProject -CompiledTestApps @('Broken.Test.app')
            $compiledAppPath = Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'TestApps') 'Broken.Test.app'
            $script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($compiledAppPath)].name = ''
            $settings = @{
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Get-TestAppsToRun -settings $settings -projectPath $projectPath } |
                Should -Throw "*Failed to read compiled test app metadata*Broken.Test.app*app name*"

            Remove-Item -Path $projectPath -Recurse -Force
        }
    }

    Context 'Code coverage source root resolution' {
        It 'Returns canonical existing project roots with deterministic deduplication' {
            $projectPath = Join-Path $TestDrive 'Project'
            foreach ($folder in @('App', 'Test')) {
                $folderPath = Join-Path $projectPath $folder
                New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $folderPath "$folder.al") `
                    -Value "codeunit 50100 $folder { }" -Encoding UTF8
            }
            $settings = @{
                appFolders  = @('App', '.\App', 'Missing')
                testFolders = @('Test')
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                Settings    = $settings
                ProjectPath = $projectPath
            } {
                $roots = @(Resolve-CodeCoverageSourceRootData -settings $Settings `
                        -projectPath $ProjectPath | ForEach-Object { "$($_.Path)" })
                $roots | Should -Be @(
                    [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'App')),
                    [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Test'))
                )
            }
        }

        It 'Uses ordinal source root ordering independent of the current culture' {
            $projectPath = Join-Path $TestDrive 'Project'
            $umlautFolder = "Project$([char]0x00E4)"
            foreach ($folder in @('Projectz', $umlautFolder)) {
                $folderPath = Join-Path $projectPath $folder
                New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $folderPath "Source.al") `
                    -Value "codeunit 50100 Source { }" -Encoding UTF8
            }
            $settings = @{
                appFolders  = @($umlautFolder, 'Projectz')
                testFolders = @()
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                Settings    = $settings
                ProjectPath = $projectPath
            } {
                $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture =
                        [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
                    $germanRoots = @(Resolve-CodeCoverageSourceRootData -settings $Settings `
                            -projectPath $ProjectPath | ForEach-Object { "$($_.Path)" })
                    [System.Threading.Thread]::CurrentThread.CurrentCulture =
                        [System.Globalization.CultureInfo]::GetCultureInfo('sv-SE')
                    $swedishRoots = @(Resolve-CodeCoverageSourceRootData -settings $Settings `
                            -projectPath $ProjectPath | ForEach-Object { "$($_.Path)" })

                    $germanRoots | Should -Be $swedishRoots
                }
                finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
                }
            }
        }

        It 'Returns aligned absolute and repository-relative root records' {
            $baseFolder = Join-Path $TestDrive 'Repository'
            $firstRoot = Join-Path $baseFolder 'First'
            $secondRoot = Join-Path $baseFolder 'Second'
            foreach ($folder in @($firstRoot, $secondRoot)) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $folder "Source.al") `
                    -Value "codeunit 50100 Source { }" -Encoding UTF8
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                BaseFolder = $baseFolder
            } {
                param($BaseFolder)
                $settings = @{
                    appFolders = @('Second', '.', 'First', 'Second')
                    testFolders = @()
                }
                $rootData = @(Resolve-CodeCoverageSourceRootData -settings $settings `
                        -projectPath $BaseFolder -baseFolder $BaseFolder)

                @($rootData.Path) | Should -Be @(
                    [System.IO.Path]::GetFullPath($BaseFolder),
                    [System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'First')),
                    [System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'Second'))
                )
                @($rootData.RelativePath) | Should -Be @('.', 'First', 'Second')
            }
        }

        It 'Rejects roots outside the repository instead of shifting exporter indexes' {
            $baseFolder = Join-Path $TestDrive 'Repository'
            $outsideRoot = Join-Path $TestDrive 'Outside'
            New-Item -Path $baseFolder -ItemType Directory -Force | Out-Null
            New-Item -Path $outsideRoot -ItemType Directory -Force | Out-Null

            InModuleScope CodeCoverageCoordinator -Parameters @{
                BaseFolder  = $baseFolder
            } {
                param($BaseFolder)
                $settings = @{
                    appFolders = @('..\Outside')
                    testFolders = @()
                }

                {
                    Resolve-CodeCoverageSourceRootData -settings $settings `
                        -projectPath $BaseFolder -baseFolder $BaseFolder
                } | Should -Throw '*outside the repository*'
            }
        }

        It 'Rejects source roots containing reparse points on Windows' -Skip:([System.IO.Path]::DirectorySeparatorChar -ne '\') {
            $baseFolder = Join-Path $TestDrive 'Repository'
            $outsideRoot = Join-Path $TestDrive 'Outside'
            $linkedRoot = Join-Path $baseFolder 'Linked'
            New-Item -Path $baseFolder -ItemType Directory -Force | Out-Null
            New-Item -Path $outsideRoot -ItemType Directory -Force | Out-Null
            New-Item -Path $linkedRoot -ItemType Junction -Target $outsideRoot | Out-Null

            InModuleScope CodeCoverageCoordinator -Parameters @{
                BaseFolder = $baseFolder
            } {
                param($BaseFolder)
                $settings = @{
                    appFolders = @('Linked')
                    testFolders = @()
                }

                {
                    Resolve-CodeCoverageSourceRootData -settings $settings `
                        -projectPath $BaseFolder -baseFolder $BaseFolder
                } | Should -Throw '*reparse point*'
            }
        }

        It 'Includes analyzed app and test roots from repository-relative projectsToTest targets' {
            $baseFolder = Join-Path $TestDrive 'Repository'
            $projectPath = Join-Path $baseFolder 'build\projects\Test Apps W1'
            $targetProject = 'build/projects/Apps W1'
            $targetProjectPath = Join-Path $baseFolder 'build\projects\Apps W1'
            $appRoot = Join-Path $baseFolder 'src\App'
            $testRoot = Join-Path $baseFolder 'src\Test'
            $undeclaredRoot = Join-Path $baseFolder 'src\Undeclared'
            foreach ($folder in @($projectPath, $targetProjectPath, $appRoot, $testRoot, $undeclaredRoot)) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath (Join-Path $appRoot "App.al") `
                -Value "codeunit 50100 App { }" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $testRoot "Test.al") `
                -Value "codeunit 50101 Test { Subtype = Test; }" -Encoding UTF8
            $settings = @{
                appFolders    = @()
                testFolders   = @()
                projectsToTest = @($targetProject)
            }
            $targetSettings = @{
                appFolders  = @('../../../src/App')
                testFolders = @('../../../src/Test')
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                Settings       = $settings
                TargetSettings = $targetSettings
                ProjectPath    = $projectPath
                BaseFolder     = $baseFolder
            } {
                param($Settings, $TargetSettings, $ProjectPath, $BaseFolder)
                Mock ReadSettings { return $TargetSettings }
                $script:analyzeRepoCalls = 0
                $analyzeRepo = {
                    param($settings, $baseFolder, $project)
                    $null = $baseFolder
                    $null = $project
                    $script:analyzeRepoCalls++
                    return $settings
                }

                $rootData = @(Resolve-CodeCoverageSourceRootData -settings $Settings `
                        -projectPath $ProjectPath -baseFolder $BaseFolder -analyzeRepo $analyzeRepo)
                $roots = @($rootData | ForEach-Object { $_.Path })

                $roots | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\App')))
                $roots | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\Test')))
                $roots | Should -Not -Contain ([System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\Undeclared')))
                @($rootData | Where-Object { $_.Path -eq
                        [System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\App')) })[0].Kind |
                    Should -Be 'app'
                @($rootData | Where-Object { $_.Path -eq
                        [System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\Test')) })[0].Kind |
                    Should -Be 'test'
                Should -Invoke ReadSettings -Times 1 -Exactly -ParameterFilter {
                    $project -eq 'build/projects/Apps W1' -and $baseFolder -eq $BaseFolder
                }
                $script:analyzeRepoCalls | Should -Be 1
            }
        }

        It 'Requires the AnalyzeRepo callback for projectsToTest source roots' {
            $baseFolder = Join-Path $TestDrive 'Repository'
            $projectPath = Join-Path $baseFolder 'Project'
            $targetProjectPath = Join-Path $baseFolder 'Target'
            New-Item -Path $projectPath -ItemType Directory -Force | Out-Null
            New-Item -Path $targetProjectPath -ItemType Directory -Force | Out-Null
            $settings = @{
                appFolders = @()
                testFolders = @()
                projectsToTest = @('Target')
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                Settings = $settings
                ProjectPath = $projectPath
                BaseFolder = $baseFolder
            } {
                param($Settings, $ProjectPath, $BaseFolder)
                Mock ReadSettings { return @{ appFolders = @(); testFolders = @() } }

                {
                    Resolve-CodeCoverageSourceRootData -settings $Settings `
                        -projectPath $ProjectPath -baseFolder $BaseFolder
                } | Should -Throw 'Analyzing projectsToTest source roots requires the AnalyzeRepo callback.'
            }
        }

        It 'Deduplicates exact target roots but retains parent, nested, and localized paths' {
            $baseFolder = Join-Path $TestDrive 'Repository'
            $projectPath = Join-Path $baseFolder 'build\projects\Test Apps W1'
            $targetOnePath = Join-Path $baseFolder 'build\projects\Apps W1'
            $targetTwoPath = Join-Path $baseFolder 'build\projects\Apps DK'
            foreach ($folder in @(
                    $projectPath,
                    $targetOnePath,
                    $targetTwoPath,
                    (Join-Path $baseFolder 'src\App'),
                    (Join-Path $baseFolder 'src\App\Nested'),
                    (Join-Path $baseFolder 'src\Localized')
                )) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }
            Set-Content -Path (Join-Path $baseFolder 'src\App\app.json') `
                -Value '{"id":"11111111-1111-1111-1111-111111111111"}' -Encoding UTF8
            Set-Content -Path (Join-Path $baseFolder 'src\Localized\app.json') `
                -Value '{"id":"11111111-1111-1111-1111-111111111111"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $baseFolder 'src\App\App.al') `
                -Value "codeunit 50100 App { }" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $baseFolder 'src\App\Nested\Nested.al') `
                -Value "codeunit 50101 Nested { }" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $baseFolder 'src\Localized\Localized.al') `
                -Value "codeunit 50102 Localized { }" -Encoding UTF8
            $settings = @{
                appFolders     = @()
                testFolders    = @()
                projectsToTest = @('build/projects/Apps W1', 'build/projects/Apps W1', 'build/projects/Apps DK')
            }
            $targetOneSettings = @{
                appFolders  = @('../../../src/App', '../../../src/App/Nested')
                testFolders = @('../../../src/App')
            }
            $targetTwoSettings = @{
                appFolders  = @('../../../src/Localized')
                testFolders = @()
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                Settings          = $settings
                TargetOneSettings = $targetOneSettings
                TargetTwoSettings = $targetTwoSettings
                ProjectPath       = $projectPath
                BaseFolder        = $baseFolder
            } {
                param($Settings, $TargetOneSettings, $TargetTwoSettings, $ProjectPath, $BaseFolder)
                Mock ReadSettings {
                    if ($project -eq 'build/projects/Apps W1') {
                        return $TargetOneSettings
                    }
                    return $TargetTwoSettings
                }
                $script:analyzeRepoCalls = 0
                $analyzeRepo = {
                    param($settings, $baseFolder, $project)
                    $null = $settings
                    $null = $baseFolder
                    $script:analyzeRepoCalls++
                    if ($project -eq 'build/projects/Apps W1') {
                        return $TargetOneSettings
                    }
                    return $TargetTwoSettings
                }

                $roots = @(Resolve-CodeCoverageSourceRootData -settings $Settings `
                        -projectPath $ProjectPath -baseFolder $BaseFolder -analyzeRepo $analyzeRepo |
                        ForEach-Object { "$($_.Path)" })

                $roots.Count | Should -Be 3
                $roots | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\App')))
                $roots | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\App\Nested')))
                $roots | Should -Contain ([System.IO.Path]::GetFullPath((Join-Path $BaseFolder 'src\Localized')))
                Should -Invoke ReadSettings -Times 2 -Exactly
                $script:analyzeRepoCalls | Should -Be 2
            }
        }

        It 'Skips configured roots that contain no recursive AL source files' {
            $projectPath = Join-Path $TestDrive 'Project'
            $emptyRoot = Join-Path $projectPath 'Empty'
            $sourceRoot = Join-Path $projectPath 'Source'
            New-Item -Path $emptyRoot -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $sourceRoot 'Nested') -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $emptyRoot 'app.json') `
                -Value '{"id":"11111111-1111-1111-1111-111111111111"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $sourceRoot 'app.json') `
                -Value '{"id":"22222222-2222-2222-2222-222222222222"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $sourceRoot 'Nested\Source.al') `
                -Value "codeunit 50100 Source { }" -Encoding UTF8
            $settings = @{
                appFolders = @('Empty', 'Source')
                testFolders = @()
            }

            InModuleScope CodeCoverageCoordinator -Parameters @{
                Settings = $settings
                ProjectPath = $projectPath
            } {
                $rootData = @(Resolve-CodeCoverageSourceRootData -settings $Settings `
                        -projectPath $ProjectPath)

                @($rootData.Path) | Should -Be @(
                    [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Source'))
                )
                @($rootData.RelativePath) | Should -Be @('Source')
                @($rootData.AppId) | Should -Be @('22222222-2222-2222-2222-222222222222')
            }
        }

    }

    Context 'Get-AlGoCodeCoverageCapability' {
        It 'Supports container platform <PlatformVersion>' -TestCases @(
            @{ PlatformVersion = '30.0.56026.0' },
            @{ PlatformVersion = '31.0.0.0' }
        ) {
            param($PlatformVersion)

            InModuleScope CodeCoverageCoordinator -Parameters @{ HandoffVersion = $PlatformVersion } {
                $capability = Get-AlGoCodeCoverageCapability `
                    -platformVersion $HandoffVersion `
                    -platformVersionReason ''

                $capability.Supported | Should -BeTrue
                $capability.Reason | Should -Match 'supports code coverage'
            }
        }
    }

    Context 'Invoke-AlGoTestRun' {
        It 'Warns that configured database restore events are not supported' {
            $projectPath = New-TestProject
            $warning = '::Warning::restoreDatabases is configured, but database restore is not currently supported by the separate RunTests action and will not be performed.'
            Mock -ModuleName RunTests Write-Host {}
            $settings = @{
                restoreDatabases               = @('BeforeEachTestApp')
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @()
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'

            Should -Invoke -ModuleName RunTests Write-Host -Times 1 -Exactly -ParameterFilter {
                $Object -eq $warning
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not emit the database restore warning for an empty setting' {
            $projectPath = New-TestProject
            $warning = '::Warning::restoreDatabases is configured, but database restore is not currently supported by the separate RunTests action and will not be performed.'
            Mock -ModuleName RunTests Write-Host {}
            $settings = @{
                restoreDatabases               = @('', ' ')
                runTestsInAllInstalledTestApps = $false
                testFolders                    = @()
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'

            Should -Invoke -ModuleName RunTests Write-Host -Times 0 -Exactly -ParameterFilter {
                $Object -eq $warning
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not run tests when there are no test apps' {
            $projectPath = New-TestProject
            $script:runnerCalls = 0
            Mock -ModuleName RunTests Invoke-AlToolTestRun { $script:runnerCalls++; return $true }
            $settings = @{ doNotRunTests = $false; runTestsInAllInstalledTestApps = $false; companyName = ''; treatTestFailuresAsWarnings = $false; testFolders = @() }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'

            $script:runnerCalls | Should -Be 0
            Test-Path (Join-Path $projectPath 'TestResults.xml') | Should -BeFalse
            Test-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml') | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies passing test results to build artifacts and preserves the root result' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $script:runnerCalls = 0
            $script:capturedOverrideKeys = @()
            $script:resultContent = '<testsuites name="passing" />'
            $override = {
                param($parameters)
                $script:runnerCalls++
                $script:capturedOverrideKeys = @($parameters.Keys)
                Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                return $true
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction           = @{
                    enabled  = $true
                    testType = ''
                }
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Not -Throw

            $script:runnerCalls | Should -Be 2
            @($script:capturedOverrideKeys | Sort-Object) | Should -Be @(
                'AppendToJUnitResultFile',
                'appName',
                'companyName',
                'containerName',
                'credential',
                'detailed',
                'disabledTests',
                'extensionId',
                'GitHubActions',
                'JUnitResultFileName',
                'returnTrueIfAllPassed'
            )
            $rootResult = Join-Path $projectPath 'TestResults.xml'
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $rootResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes an override-specific testType without built-in validation' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                throw 'The built-in runner should not be called'
            }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedTestType = $null
            $override = {
                param($parameters)
                $script:capturedTestType = $parameters.testType
                return $true
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction           = @{
                    enabled  = $true
                    testType = 'Legacy'
                }
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                -credential $testCredential -runTestsOverride $override

            $script:capturedTestType | Should -Be 'Legacy'
            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 0 -Exactly
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not create an artifact when test execution produces no result file' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            Set-Content -Path $artifactResult -Value '<testsuites name="stale" />' -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride { return $true }

            Test-Path (Join-Path $projectPath 'TestResults.xml') | Should -BeFalse
            Test-Path $artifactResult | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Invokes only the normal test app when compiled artifacts also contain a BCPT app' {
            $projectPath = New-TestProject -CompiledTestApps @('Normal.Test.app', 'Performance.Test.app')
            $testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            $script:invokedExtensionIds = @()
            $override = {
                param($parameters)
                $script:invokedExtensionIds += "$($parameters.extensionId)"
                return $true
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @($testFolders[0])
                bcptTestFolders                = @($testFolders[1])
            }
            $normalAppPath = Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'TestApps') 'Normal.Test.app'
            $normalAppId = "$($script:compiledAppMetadataByPath[[System.IO.Path]::GetFullPath($normalAppPath)].id)"

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:invokedExtensionIds | Should -Be @($normalAppId)
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Uses selected app metadata without reading the compiled app again during execution' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                -credential $testCredential -runTestsOverride { return $true }

            Should -Invoke -ModuleName RunTests Get-AppJsonFromAppFile -Times 1 -Exactly
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes nested and project-wide disabled tests to an override as recursive hashtables' {
            $appId = [Guid]::NewGuid().ToString()
            $otherAppId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }

            $testFolder = Join-Path $projectPath 'TestApp'
            $nestedFolder = Join-Path $testFolder 'Nested'
            New-Item -Path $nestedFolder -ItemType Directory -Force | Out-Null
            @{ id = $appId } | ConvertTo-Json | Set-Content -Path (Join-Path $testFolder 'app.json') -Encoding UTF8
            @(
                @{
                    codeunitName = 'Nested Tests'
                    method       = @('TestOne')
                    metadata     = @{ source = 'nested'; issue = @{ id = 123 } }
                }
            ) | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $nestedFolder 'disabledTests.json') -Encoding UTF8

            $otherTestFolder = Join-Path $projectPath 'OtherTestApp'
            New-Item -Path $otherTestFolder -ItemType Directory -Force | Out-Null
            @{ id = $otherAppId } | ConvertTo-Json | Set-Content -Path (Join-Path $otherTestFolder 'app.json') -Encoding UTF8
            @(@{ codeunitName = 'Other Tests'; method = 'Ignored' }) | ConvertTo-Json | Set-Content -Path (Join-Path $otherTestFolder 'disabledTests.json') -Encoding UTF8

            $projectSettingsFolder = Join-Path $projectPath '.AL-Go'
            New-Item -Path $projectSettingsFolder -ItemType Directory -Force | Out-Null
            @(
                @{ codeunitName = 'Project Tests'; method = 'TestTwo'; metadata = @{ source = 'project-wide' } }
            ) | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $projectSettingsFolder "$appId.disabledTests.json") -Encoding UTF8

            $script:capturedDisabledTests = @()
            $override = { param($parameters) $script:capturedDisabledTests = @($parameters.disabledTests); return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @('TestApp', 'OtherTestApp')
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedDisabledTests.Count | Should -Be 2
            @($script:capturedDisabledTests.codeunitName | Sort-Object) |
                Should -Be @('Nested Tests', 'Project Tests')
            $nestedDisabledTest = $script:capturedDisabledTests | Where-Object { $_.codeunitName -eq 'Nested Tests' }
            $nestedDisabledTest | Should -BeOfType System.Collections.Hashtable
            $nestedDisabledTest.metadata | Should -BeOfType System.Collections.Hashtable
            $nestedDisabledTest.metadata.issue | Should -BeOfType System.Collections.Hashtable
            $nestedDisabledTest.metadata.issue.id | Should -Be 123
            $nestedDisabledTest.metadata.source | Should -Be 'nested'
            @($nestedDisabledTest.method) | Should -Be @('TestOne')
            $projectDisabledTest = $script:capturedDisabledTests | Where-Object { $_.codeunitName -eq 'Project Tests' }
            $projectDisabledTest.metadata.source | Should -Be 'project-wide'
            $projectDisabledTest.method | Should -Be 'TestTwo'
            $script:capturedDisabledTests.codeunitName | Should -Not -Contain 'Other Tests'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Fails with the disabled tests file path when its JSON is invalid' {
            $appId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }
            $testFolder = Join-Path $projectPath 'TestApp'
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            @{ id = $appId } | ConvertTo-Json | Set-Content -Path (Join-Path $testFolder 'app.json') -Encoding UTF8
            Set-Content -Path (Join-Path $testFolder 'disabledTests.json') -Value '{invalid' -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @('TestApp')
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride { return $true } } |
                Should -Throw '*disabledTests.json*'

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies failed test results before throwing when treatTestFailuresAsWarnings is not set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:resultContent = '<testsuites name="hard-failure" />'
            $override = {
                param($parameters)
                Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                return $false
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } |
                Should -Throw '*There are test failures*'

            $rootResult = Join-Path $projectPath 'TestResults.xml'
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $rootResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies failed test results when treatTestFailuresAsWarnings is set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:resultContent = '<testsuites name="warning-failure" />'
            $override = {
                param($parameters)
                Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                return $false
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } | Should -Not -Throw

            $rootResult = Join-Path $projectPath 'TestResults.xml'
            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $rootResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Copies partial test results before rethrowing a later runner error' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $script:runnerCalls = 0
            $script:resultContent = '<testsuites name="partial-runner-error" />'
            $override = {
                param($parameters)
                $script:runnerCalls++
                if ($script:runnerCalls -eq 1) {
                    Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                    return $true
                }
                throw 'second app runner failed'
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } |
                Should -Throw '*second app runner failed*'

            $artifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            (Get-Content -Path $artifactResult -Raw -Encoding UTF8).Trim() | Should -Be $script:resultContent
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Preserves a later runner error when copying partial results also fails' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $script:runnerCalls = 0
            $script:resultContent = '<testsuites name="partial-copy-error" />'
            $script:partialArtifactResult = Join-Path (Join-Path $projectPath '.buildartifacts') 'TestResults.xml'
            $override = {
                param($parameters)
                $script:runnerCalls++
                if ($script:runnerCalls -eq 1) {
                    Set-Content -Path $parameters.JUnitResultFileName -Value $script:resultContent -Encoding UTF8
                    return $true
                }
                throw 'second app runner failed'
            }
            Mock -ModuleName RunTests Copy-Item { throw 'partial copy blocked' } -ParameterFilter {
                $Destination -eq $script:partialArtifactResult
            }
            Mock -ModuleName RunTests OutputWarning {}
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } |
                Should -Throw '*second app runner failed*'

            Test-Path $script:partialArtifactResult | Should -BeFalse
            Should -Invoke -ModuleName RunTests OutputWarning -Times 1 -Exactly -ParameterFilter {
                $message -like '*test results could not be copied to build artifacts*partial copy blocked*'
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Surfaces artifact copy errors before a test failure message' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $override = {
                param($parameters)
                Set-Content -Path $parameters.JUnitResultFileName -Value '<testsuites name="copy-error" />' -Encoding UTF8
                return $false
            }
            Mock -ModuleName RunTests Copy-Item { throw 'copy blocked' }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override } |
                Should -Throw '*Failed to copy test results*copy blocked*'

            Should -Invoke -ModuleName RunTests Get-BcContainerEventLog -Times 1 -Exactly
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes GitHubActions severity error when treatTestFailuresAsWarnings is not set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedSeverity = $null
            $override = { param($parameters) $script:capturedSeverity = $parameters.GitHubActions; return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedSeverity | Should -Be 'error'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes GitHubActions severity warning when treatTestFailuresAsWarnings is set' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:capturedSeverity = $null
            $override = { param($parameters) $script:capturedSeverity = $parameters.GitHubActions; return $true }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:capturedSeverity | Should -Be 'warning'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Builds a parameter set that is valid for the real Run-TestsInBcContainer cmdlet' {
            # Guard against parameter drift: every key/value passed to the BcContainerHelper test
            # runner is validated against the real cmdlet signature (parameter names and ValidateSet
            # values). This catches invalid parameter names and out-of-set values locally instead of
            # only surfacing them in CI, where the real cmdlet is actually invoked.
            $compatibleModule = Get-Module -ListAvailable -Name BcContainerHelper |
                Where-Object { $_.Version -ge [version] '6.1.9' } |
                Sort-Object Version -Descending |
                Select-Object -First 1
            if (-not $compatibleModule) {
                Set-ItResult -Skipped -Because 'BcContainerHelper 6.1.9 or later is not available in this environment'
                return
            }

            $compatibleModulePath = Join-Path $compatibleModule.ModuleBase 'BcContainerHelper.psd1'
            if (-not (Test-Path -LiteralPath $compatibleModulePath -PathType Leaf)) {
                $compatibleModulePath = $compatibleModule.Path
            }
            $previousModulePaths = @(
                foreach ($previousModule in @(Get-Module -Name BcContainerHelper)) {
                    $manifestPath = Join-Path $previousModule.ModuleBase "$($previousModule.Name).psd1"
                    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                        $manifestPath
                    }
                    else {
                        $previousModule.Path
                    }
                }
            )
            $loadedModule = Import-Module $compatibleModulePath -DisableNameChecking -Force -PassThru
            try {
                $command = Get-Command -Name 'Run-TestsInBcContainer' -Module $loadedModule.Name -ErrorAction Stop
                if (($command -is [System.Management.Automation.AliasInfo]) -and $command.ResolvedCommand) {
                    $command = $command.ResolvedCommand
                }

                $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
                $script:capturedParams = $null
                $override = { param($parameters) $script:capturedParams = $parameters; return $true }
                $settings = @{
                    doNotRunTests                  = $false
                    runTestsInAllInstalledTestApps = $false
                    companyName                    = ''
                    treatTestFailuresAsWarnings    = $false
                    testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                }

                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' -credential $testCredential -runTestsOverride $override

                $script:capturedParams | Should -Not -BeNullOrEmpty
                foreach ($key in $script:capturedParams.Keys) {
                    $parameter = $command.Parameters[$key]
                    $parameter | Should -Not -BeNullOrEmpty -Because "'$key' must be a real parameter of Run-TestsInBcContainer"

                    $validateSet = $parameter.Attributes |
                        Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                        Select-Object -First 1
                    if ($validateSet) {
                        $validateSet.ValidValues | Should -Contain $script:capturedParams[$key] -Because "the value for '$key' must be one of its allowed ValidateSet values"
                    }
                }

                Remove-Item -Path $projectPath -Recurse -Force
            }
            finally {
                Remove-Module -ModuleInfo $loadedModule -Force -ErrorAction SilentlyContinue
                foreach ($previousModulePath in $previousModulePaths) {
                    Import-Module $previousModulePath -DisableNameChecking -Force
                }
            }
        }
    }

    Context 'Invoke-AlGoTestRun (default AlTool runner)' {
        It 'Runs the AlTool runner for every test app when no override is supplied' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun { return $true }
            Mock -ModuleName RunTests OutputWarning {}
            $script:alToolPathResolutionCount = 0
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction           = @{
                    enabled  = $true
                    testType = ''
                }
            }

            $getAlToolPath = {
                $script:alToolPathResolutionCount++
                return 'C:\dotnet-tools\al.exe'
            }
            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                    -credential $testCredential -getAlToolPath $getAlToolPath `
                    -containerPlatformVersion 'not-a-version' `
                    -containerPlatformVersionReason 'lookup should be ignored'
            } | Should -Not -Throw

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 2 -Exactly
            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 2 -Exactly -ParameterFilter {
                $TestType -eq '' -and $AlToolPath -eq 'C:\dotnet-tools\al.exe'
            }
            $script:alToolPathResolutionCount | Should -Be 1
            Should -Invoke -ModuleName RunTests OutputWarning -Times 0 -Exactly
            Test-Path -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') 'coverage-status.json'
            ) | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Tracks supported coverage completeness in unique stable output directories for every app' {
            $script:capturedCoverageRuns = @()
            $script:coverageStatusObservedDuringRuns = @()
            $script:coverageInvocation = 0
            Mock -ModuleName RunTests Get-AlGoCodeCoverageCapability {
                return @{ Supported = $true; Reason = "" }
            }
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                param(
                    $ExtensionId,
                    $AppName,
                    $CoverageOutputPath,
                    [string[]] $CoverageFormats,
                    [string[]] $CoverageSourceRoots,
                    [ref] $CoverageIsComplete
                )
                $coverageRootAtInvocation = Split-Path -Path $CoverageOutputPath -Parent
                $script:coverageStatusObservedDuringRuns += Test-Path -LiteralPath (
                    Join-Path $coverageRootAtInvocation 'coverage-status.json'
                )
                $script:capturedCoverageRuns += [PSCustomObject]@{
                    ExtensionId        = $ExtensionId
                    AppName            = $AppName
                    CoverageOutputPath = $CoverageOutputPath
                    CoverageFormats    = @($CoverageFormats)
                    CoverageSourceRoots = @($CoverageSourceRoots)
                }
                $script:coverageInvocation++
                $isComplete = ($script:coverageInvocation -eq 1)
                New-Item -Path $CoverageOutputPath -ItemType Directory -Force | Out-Null
                @{
                    schemaVersion = '1.0'
                    coverageMode = 'line'
                    complete = $isComplete
                } | ConvertTo-Json | Set-Content -LiteralPath (
                    Join-Path $CoverageOutputPath 'coverage.bc.json'
                ) -Encoding UTF8
                Set-Content -LiteralPath (
                    Join-Path $CoverageOutputPath 'coverage.cobertura.xml'
                ) -Value '<coverage />' -Encoding UTF8
                $CoverageIsComplete.Value = $isComplete
                return $true
            }
            $appOneId = [Guid]::NewGuid().ToString()
            $appTwoId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app') -CompiledAppIds @{
                'App1.Test.app' = $appOneId
                'App2.Test.app' = $appTwoId
            }
            New-Item -Path (Join-Path $projectPath 'App') -ItemType Directory -Force | Out-Null
            @{
                id = '11111111-1111-1111-1111-111111111111'
                name = 'Coverage App'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectPath 'App\app.json') -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $projectPath 'App\CoverageApp.al') `
                -Value "codeunit 50100 CoverageApp { }" -Encoding UTF8
            $testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                appFolders                     = @('App')
                testFolders                    = $testFolders
                useSeparateTestAction           = @{
                    enabled                       = $true
                    testType                      = ''
                    codeCoverageEnabled           = $true
                    codeCoverageGenerateCobertura = $true
                }
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                -project 'Projects/Coverage' -projectName 'Coverage Project' -buildMode 'Clean' `
                -containerName 'test' -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe' `
                -containerPlatformVersion '30.0.56026.0'

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 2 -Exactly
            Should -Invoke -ModuleName RunTests Get-AlGoCodeCoverageCapability -Times 1 -Exactly
            $script:capturedCoverageRuns.Count | Should -Be 2
            $script:coverageStatusObservedDuringRuns | Should -Be @($false, $false)
            $script:capturedCoverageRuns[0].CoverageFormats | Should -Be @('bc-json', 'cobertura')
            $script:capturedCoverageRuns[0].CoverageSourceRoots | Should -Contain (
                [System.IO.Path]::GetFullPath((Join-Path $projectPath 'App'))
            )
            foreach ($testFolder in $testFolders) {
                $script:capturedCoverageRuns[0].CoverageSourceRoots | Should -Contain (
                    [System.IO.Path]::GetFullPath((Join-Path $projectPath $testFolder))
                )
            }
            $script:capturedCoverageRuns[0].CoverageSourceRoots.Count | Should -Be 3
            $script:capturedCoverageRuns[0].CoverageOutputPath |
                Should -Be (Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') $appOneId)
            $script:capturedCoverageRuns[1].CoverageOutputPath |
                Should -Be (Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') $appTwoId)
            $script:capturedCoverageRuns[0].CoverageOutputPath |
                Should -Not -Be $script:capturedCoverageRuns[1].CoverageOutputPath
            $coverageRoot = Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage'
            $coverageStatus = Get-Content -LiteralPath (Join-Path $coverageRoot 'coverage-status.json') `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            $coverageStatus.PSObject.Properties.Name |
                Should -Be @('project', 'projectName', 'buildMode', 'formats', 'sourceRoots',
                    'sourceRootDetails', 'runs')
            $coverageStatus.project | Should -Be 'Projects/Coverage'
            $coverageStatus.projectName | Should -Be 'Coverage Project'
            $coverageStatus.buildMode | Should -Be 'Clean'
            $coverageStatus.formats | Should -Be @('bc-json', 'cobertura')
            $coverageStatus.sourceRoots | Should -Be @('App', 'TestApp1', 'TestApp2')
            $coverageStatus.sourceRootDetails.Count | Should -Be 3
            @($coverageStatus.sourceRootDetails | ForEach-Object { $_.path }) |
                Should -Be $coverageStatus.sourceRoots
            @($coverageStatus.sourceRootDetails | ForEach-Object { $_.kind }) |
                Should -Be @('app', 'test', 'test')
            $coverageStatus.sourceRootDetails[0].appId |
                Should -Be '11111111-1111-1111-1111-111111111111'
            $coverageStatus.sourceRootDetails[0].appName | Should -Be 'Coverage App'
            $coverageStatus.runs.Count | Should -Be 2
            $coverageStatus.runs[0].PSObject.Properties.Name |
                Should -Be @('appId', 'appName', 'outputDirectory', 'state')
            $coverageStatus.runs[0].appId | Should -Be $appOneId
            $coverageStatus.runs[0].outputDirectory | Should -Be "CodeCoverage/$appOneId"
            $coverageStatusByAppId = @{}
            foreach ($run in $coverageStatus.runs) {
                $coverageStatusByAppId[$run.appId] = $run.state
            }
            $coverageStatusByAppId[$appOneId] | Should -Be 'complete'
            $coverageStatusByAppId[$appTwoId] | Should -Be 'incomplete'
            @($coverageStatus.PSObject.Properties.Name) | Should -Not -Contain 'aggregate'
            @(Get-ChildItem -LiteralPath $coverageRoot -Filter 'coverage.bc.json' -File -Recurse).Count |
                Should -Be 2
            ($coverageStatus | ConvertTo-Json -Depth 5) | Should -Not -Match 'admin|password|diagnostic'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Warns and runs normally without coverage when <Case>' -TestCases @(
            @{
                Case            = 'the platform is below the boundary'
                PlatformVersion = '30.0.56025.999'
                HandoffReason   = ''
            },
            @{
                Case            = 'the platform version is malformed'
                PlatformVersion = 'not-a-version'
                HandoffReason   = ''
            },
            @{
                Case            = 'platform version lookup failed'
                PlatformVersion = ''
                HandoffReason   = 'Get-BcContainerPlatformVersion failed (RuntimeException).'
            },
            @{
                Case            = 'the platform handoff is missing'
                PlatformVersion = ''
                HandoffReason   = ''
            }
        ) {
            param($Case, $PlatformVersion, $HandoffReason)

            $null = $Case
            Mock -ModuleName RunTests OutputWarning {}
            $script:coverageDowngradeBoundParameters = @()
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                $script:coverageDowngradeBoundParameters = @($PSBoundParameters.Keys)
                return $true
            }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $staleCoveragePath = Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') 'stale-app'
            New-Item -Path $staleCoveragePath -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $staleCoveragePath 'coverage.bc.json') -Value '{}' -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction           = @{
                    enabled                       = $true
                    testType                      = ''
                    codeCoverageEnabled           = $true
                    codeCoverageGenerateCobertura = $true
                }
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                -containerName 'test' -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe' `
                -containerPlatformVersion $PlatformVersion `
                -containerPlatformVersionReason $HandoffReason

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 1 -Exactly
            $script:coverageDowngradeBoundParameters | Should -Not -Contain 'CoverageMode'
            $script:coverageDowngradeBoundParameters | Should -Not -Contain 'CoverageOutputPath'
            Should -Invoke -ModuleName RunTests OutputWarning -Times 1 -Exactly -ParameterFilter {
                $message -like '*container platform 30.0.56026.0*continue without coverage*'
            }
            $coverageRoot = Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage'
            Test-Path -LiteralPath $staleCoveragePath | Should -BeFalse
            $coverageStatus = Get-Content -LiteralPath (Join-Path $coverageRoot 'coverage-status.json') `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            $coverageStatus.runs.Count | Should -Be 1
            $coverageStatus.runs[0].state | Should -Be 'unsupported'
            Test-Path -LiteralPath (Join-Path $coverageRoot $coverageStatus.runs[0].appId) |
                Should -BeFalse
            ($coverageStatus | ConvertTo-Json -Depth 5) | Should -Not -Match 'admin|password|platform'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Propagates coverage failure without downgrading after platform support is established' {
            Mock -ModuleName RunTests OutputWarning {}
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                throw 'coverage export failed'
            }
            $appOneId = [Guid]::NewGuid().ToString()
            $appTwoId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app') -CompiledAppIds @{
                'App1.Test.app' = $appOneId
                'App2.Test.app' = $appTwoId
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction           = @{
                    enabled                       = $true
                    testType                      = ''
                    codeCoverageEnabled           = $true
                    codeCoverageGenerateCobertura = $false
                }
            }

            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                    -containerName 'test' -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe' `
                    -containerPlatformVersion '30.0.56026.0'
            } | Should -Throw '*coverage export failed*'

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 1 -Exactly -ParameterFilter {
                $CoverageFormats -eq @('bc-json') -and
                -not [string]::IsNullOrWhiteSpace($CoverageOutputPath)
            }
            Should -Invoke -ModuleName RunTests OutputWarning -Times 0 -Exactly
            $coverageStatus = Get-Content -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') 'coverage-status.json'
            ) -Raw -Encoding UTF8 | ConvertFrom-Json
            $coverageStatusByAppId = @{}
            foreach ($run in $coverageStatus.runs) {
                $coverageStatusByAppId[$run.appId] = $run.state
            }
            $coverageStatusByAppId[$appOneId] | Should -Be 'failed'
            $coverageStatusByAppId[$appTwoId] | Should -Be 'failed'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Maps useSeparateTestAction.testType and other built-in runner parameters' {
            $appId = [Guid]::NewGuid().ToString()
            $script:capturedAlToolParams = $null
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                param(
                    $ContainerName,
                    [System.Management.Automation.PSCredential] $Credential,
                    $ExtensionId,
                    $AppName,
                    $CompanyName,
                    $Tenant,
                    $TestType,
                    [hashtable[]] $DisabledTests,
                    $AlToolPath,
                    $JUnitResultFileName
                )
                $script:capturedAlToolParams = @{
                    Keys                = @($PSBoundParameters.Keys)
                    ContainerName       = $ContainerName
                    Credential          = $Credential
                    ExtensionId         = $ExtensionId
                    AppName             = $AppName
                    CompanyName         = $CompanyName
                    Tenant              = $Tenant
                    TestType            = $TestType
                    DisabledTests       = @($DisabledTests)
                    AlToolPath          = $AlToolPath
                    JUnitResultFileName = $JUnitResultFileName
                }
                return $true
            }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = 'CRONUS'
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction           = @{
                    enabled  = $true
                    testType = 'IntegrationTest'
                }
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'mycontainer' -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 1 -Exactly
            @($script:capturedAlToolParams.Keys | Sort-Object) | Should -Be @(
                'AlToolPath',
                'AppName',
                'CompanyName',
                'ContainerName',
                'Credential',
                'DisabledTests',
                'ExtensionId',
                'JUnitResultFileName',
                'Tenant',
                'TestType'
            )
            $script:capturedAlToolParams.ContainerName | Should -Be 'mycontainer'
            $script:capturedAlToolParams.Credential | Should -BeOfType [System.Management.Automation.PSCredential]
            $script:capturedAlToolParams.ExtensionId | Should -Be $appId
            $script:capturedAlToolParams.AppName | Should -Be 'App1.Test'
            $script:capturedAlToolParams.CompanyName | Should -Be 'CRONUS'
            $script:capturedAlToolParams.AlToolPath | Should -Be 'C:\dotnet-tools\al.exe'
            $script:capturedAlToolParams.Tenant | Should -Be 'default'
            $script:capturedAlToolParams.TestType | Should -Be 'IntegrationTest'
            $script:capturedAlToolParams.DisabledTests.Count | Should -Be 0
            $script:capturedAlToolParams.JUnitResultFileName | Should -Be (Join-Path $projectPath 'TestResults.xml')
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Passes project-wide disabled tests to the AlTool runner' {
            $appId = [Guid]::NewGuid().ToString()
            $script:capturedAlToolParams = $null
            Mock -ModuleName RunTests Invoke-AlToolTestRun {
                param([hashtable[]] $DisabledTests)
                $script:capturedAlToolParams = @($DisabledTests)
                return $true
            }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app') -CompiledAppIds @{ 'App1.Test.app' = $appId }
            @(@{ codeunitName = 'Project Tests'; method = 'TestOne' }) | ConvertTo-Json |
                Set-Content -Path (Join-Path $projectPath "$appId.disabledTests.json") -Encoding UTF8
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'

            Should -Invoke -ModuleName RunTests Invoke-AlToolTestRun -Times 1 -Exactly
            $script:capturedAlToolParams.Count | Should -Be 1
            $script:capturedAlToolParams[0] | Should -BeOfType System.Collections.Hashtable
            $script:capturedAlToolParams[0].codeunitName | Should -Be 'Project Tests'
            $script:capturedAlToolParams[0].method | Should -Be 'TestOne'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Throws when the AlTool runner reports failure and treatTestFailuresAsWarnings is not set' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun { return $false }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                    -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'
            } | Should -Throw

            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not throw when the AlTool runner reports failure but treatTestFailuresAsWarnings is set' {
            Mock -ModuleName RunTests Invoke-AlToolTestRun { return $false }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $true
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'test' `
                    -credential $testCredential -alToolPath 'C:\dotnet-tools\al.exe'
            } | Should -Not -Throw

            Remove-Item -Path $projectPath -Recurse -Force
        }
    }

    Context 'Invoke-AlGoTestRun coverage-aware original override' {
        It 'Fails closed when an override ignores supported coverage parameters' {
            Mock -ModuleName RunTests OutputWarning {}
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:outdatedOverrideCalls = 0
            $override = {
                [CmdletBinding()]
                param([hashtable] $parameters)
                $null = $parameters
                $script:outdatedOverrideCalls++
                return $true
            }
            $settings = @{
                doNotRunTests = $false
                runTestsInAllInstalledTestApps = $false
                companyName = ''
                treatTestFailuresAsWarnings = $false
                testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction = @{
                    enabled = $true
                    testType = ''
                    codeCoverageEnabled = $true
                    codeCoverageGenerateCobertura = $false
                }
            }

            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                    -containerName 'test' -credential $testCredential -runTestsOverride $override `
                    -alToolPath 'C:\dotnet-tools\al.exe' `
                    -containerPlatformVersion '30.0.56026.0'
            } | Should -Throw '*did not report whether coverage is complete*'

            $script:outdatedOverrideCalls | Should -Be 1
            $status = Get-Content -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') `
                    'coverage-status.json'
            ) -Raw -Encoding UTF8 | ConvertFrom-Json
            $status.runs[0].state | Should -Be 'failed'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Does not add coverage parameters when coverage is disabled' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $existingCoveragePath = Join-Path (
                Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage'
            ) 'sentinel.txt'
            New-Item -Path (Split-Path $existingCoveragePath -Parent) -ItemType Directory -Force |
                Out-Null
            Set-Content -LiteralPath $existingCoveragePath -Value 'existing' -Encoding UTF8
            $script:disabledCoverageCalls = 0
            $override = {
                param([hashtable] $parameters)
                $args | Should -BeNullOrEmpty
                @($parameters.Keys | Where-Object { $_ -like 'codeCoverage*' }).Count |
                    Should -Be 0
                $script:disabledCoverageCalls++
                return $true
            }
            $settings = @{
                doNotRunTests = $false
                runTestsInAllInstalledTestApps = $false
                companyName = ''
                treatTestFailuresAsWarnings = $false
                testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction = @{
                    enabled = $true
                    testType = 'Legacy'
                    codeCoverageEnabled = $false
                }
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                -containerName 'test' -credential $testCredential -runTestsOverride $override

            $script:disabledCoverageCalls | Should -Be 2
            Test-Path -LiteralPath $existingCoveragePath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (
                Join-Path (Split-Path $existingCoveragePath -Parent) 'coverage-status.json'
            ) | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Invokes the thin override once per app with authoritative coverage parameters' {
            $firstAppId = [Guid]::NewGuid().ToString()
            $secondAppId = [Guid]::NewGuid().ToString()
            $projectPath = New-TestProject -CompiledTestApps @(
                'App1.Test.app',
                'App2.Test.app'
            ) -CompiledAppIds @{
                'App1.Test.app' = $firstAppId
                'App2.Test.app' = $secondAppId
            }
            $appFolder = Join-Path $projectPath 'App'
            New-Item -Path $appFolder -ItemType Directory -Force | Out-Null
            @{
                id = '11111111-1111-1111-1111-111111111111'
                name = 'Regular App'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appFolder 'app.json') -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $appFolder 'RegularApp.al') `
                -Value "codeunit 50100 RegularApp { }" -Encoding UTF8
            $targetProject = 'TargetProject'
            $targetProjectPath = Join-Path $projectPath $targetProject
            $targetAppPath = Join-Path $targetProjectPath 'TargetApp'
            New-Item -Path $targetAppPath -ItemType Directory -Force | Out-Null
            @{
                id = '33333333-3333-3333-3333-333333333333'
                name = 'Target App'
            } | ConvertTo-Json | Set-Content -LiteralPath (
                Join-Path $targetAppPath 'app.json'
            ) -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $targetAppPath 'TargetApp.al') `
                -Value "codeunit 50101 TargetApp { }" -Encoding UTF8
            $targetSettingsPath = Join-Path $targetProjectPath '.AL-Go'
            New-Item -Path $targetSettingsPath -ItemType Directory -Force | Out-Null
            @{
                appFolders = @('TargetApp')
                testFolders = @()
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (
                Join-Path $targetSettingsPath 'settings.json'
            ) -Encoding UTF8
            $settings = @{
                doNotRunTests = $false
                runTestsInAllInstalledTestApps = $false
                companyName = 'CRONUS'
                treatTestFailuresAsWarnings = $false
                appFolders = @('App')
                testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                projectsToTest = @($targetProject)
                useSeparateTestAction = @{
                    enabled = $true
                    testType = 'IntegrationTest'
                    codeCoverageEnabled = $true
                    codeCoverageGenerateCobertura = $true
                }
            }
            $script:coverageOverrideCalls = 0
            $script:coverageOverrideParameters = @()
            $script:coverageAnalyzeRepoCalls = 0
            $analyzeRepo = {
                param($settings, $baseFolder, $project)
                $null = $baseFolder
                $null = $project
                $script:coverageAnalyzeRepoCalls++
                return $settings
            }
            $override = {
                param([hashtable] $parameters)
                $script:coverageOverrideCalls++
                $parameters.credential | Should -Be $testCredential
                $script:coverageOverrideParameters += @{
                    CoverageKeys = @($parameters.Keys | Where-Object { $_ -like 'codeCoverage*' })
                    OutputPath = $parameters.codeCoverageOutputPath
                    SourceRoots = @($parameters.codeCoverageSourceRoots)
                    ApplicationIds = @($parameters.codeCoverageApplicationIds)
                    AlToolModulePath = $parameters.codeCoverageAlToolModulePath
                    AlToolPath = $parameters.codeCoverageAlToolPath
                }
                New-Item -Path $parameters.codeCoverageOutputPath `
                    -ItemType Directory -Force | Out-Null
                @{
                    schemaVersion = '1.0'
                    coverageMode = 'line'
                    complete = $true
                    diagnostics = @()
                    sources = @()
                    tests = @()
                    procedureEdges = @()
                    methods = @()
                    lines = @()
                } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (
                    Join-Path $parameters.codeCoverageOutputPath 'coverage.bc.json'
                ) -Encoding UTF8
                Set-Content -LiteralPath (
                    Join-Path $parameters.codeCoverageOutputPath 'coverage.cobertura.xml'
                ) -Value '<coverage />' -Encoding UTF8
                $parameters.codeCoverageIsComplete = $true
                return $true
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                -baseFolder $projectPath -project '.' -projectName 'Coverage Project' `
                -buildMode 'Default' -containerName 'test' -credential $testCredential `
                -runTestsOverride $override -analyzeRepo $analyzeRepo `
                -alToolPath 'C:\dotnet-tools\al.exe' `
                -containerPlatformVersion '30.0.56026.0'

            $script:coverageOverrideCalls | Should -Be 2
            $script:coverageAnalyzeRepoCalls | Should -Be 1
            @($script:coverageOverrideParameters.OutputPath | Select-Object -Unique).Count |
                Should -Be 2
            foreach ($coverageParameters in $script:coverageOverrideParameters) {
                @($coverageParameters.CoverageKeys | Sort-Object) | Should -Be @(
                    'codeCoverageAlToolModulePath',
                    'codeCoverageAlToolPath',
                    'codeCoverageApplicationIds',
                    'codeCoverageFormats',
                    'codeCoverageIsComplete',
                    'codeCoverageOutputPath',
                    'codeCoverageSourceRoots'
                )
                $coverageParameters.AlToolPath | Should -Be 'C:\dotnet-tools\al.exe'
                $coverageParameters.AlToolModulePath | Should -Match 'AlToolTestRunner\.psm1$'
                $coverageParameters.SourceRoots | Should -Contain $appFolder
                $coverageParameters.SourceRoots | Should -Contain $targetAppPath
                $coverageParameters.ApplicationIds | Should -Be @(
                    '11111111-1111-1111-1111-111111111111',
                    '33333333-3333-3333-3333-333333333333'
                )
            }
            $status = Get-Content -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') `
                    'coverage-status.json'
            ) -Raw -Encoding UTF8 | ConvertFrom-Json
            @($status.runs.appId) | Should -Be @($firstAppId, $secondAppId)
            @($status.runs.state) | Should -Be @('complete', 'complete')
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Fails closed when the override does not produce its allocated artifacts' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests = $false
                runTestsInAllInstalledTestApps = $false
                companyName = ''
                treatTestFailuresAsWarnings = $false
                appFolders = @()
                testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction = @{
                    enabled = $true
                    testType = 'IntegrationTest'
                    codeCoverageEnabled = $true
                    codeCoverageGenerateCobertura = $false
                }
            }
            $override = {
                param([hashtable] $parameters)
                $parameters.codeCoverageIsComplete = $true
                return $true
            }

            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                    -containerName 'test' -credential $testCredential `
                    -runTestsOverride $override -alToolPath 'C:\dotnet-tools\al.exe' `
                    -containerPlatformVersion '30.0.56026.0'
            } | Should -Throw "*expected 'bc-json' coverage artifact*"

            $status = Get-Content -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') `
                    'coverage-status.json'
            ) -Raw -Encoding UTF8 | ConvertFrom-Json
            $status.runs[0].state | Should -Be 'failed'
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Uses historical override parameters when coverage is unsupported' {
            Mock -ModuleName RunTests OutputWarning {}
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app', 'App2.Test.app')
            $settings = @{
                doNotRunTests = $false
                runTestsInAllInstalledTestApps = $false
                companyName = ''
                treatTestFailuresAsWarnings = $false
                testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction = @{
                    enabled = $true
                    testType = 'IntegrationTest'
                    codeCoverageEnabled = $true
                    codeCoverageGenerateCobertura = $false
                }
            }
            $script:unsupportedCoverageCalls = 0
            $override = {
                param([hashtable] $parameters)
                @($parameters.Keys | Where-Object { $_ -like 'codeCoverage*' }).Count |
                    Should -Be 0
                $args | Should -BeNullOrEmpty
                $script:unsupportedCoverageCalls++
                return $true
            }
            $getAlToolPath = {
                throw 'AlTool must not be resolved for unsupported override coverage.'
            }

            Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                -containerName 'test' -credential $testCredential -runTestsOverride $override `
                -getAlToolPath $getAlToolPath `
                -containerPlatformVersion '30.0.56025.999'

            $script:unsupportedCoverageCalls | Should -Be 2
            Should -Invoke -ModuleName RunTests OutputWarning -Times 1 -Exactly -ParameterFilter {
                $message -like '*container platform 30.0.56026.0*'
            }
            $status = Get-Content -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') `
                    'coverage-status.json'
            ) -Raw -Encoding UTF8 | ConvertFrom-Json
            @($status.runs.state) | Should -Be @('unsupported', 'unsupported')
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Retains valid coverage when the override reports failed tests' {
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $settings = @{
                doNotRunTests = $false
                runTestsInAllInstalledTestApps = $false
                companyName = ''
                treatTestFailuresAsWarnings = $false
                testFolders = @(Get-TestFoldersForProject -ProjectPath $projectPath)
                useSeparateTestAction = @{
                    enabled = $true
                    testType = 'Uncategorized'
                    codeCoverageEnabled = $true
                    codeCoverageGenerateCobertura = $false
                }
            }
            $override = {
                param([hashtable] $parameters)
                New-Item -Path $parameters.codeCoverageOutputPath `
                    -ItemType Directory -Force | Out-Null
                @{
                    schemaVersion = '1.0'
                    coverageMode = 'line'
                    complete = $true
                    diagnostics = @()
                    sources = @()
                    tests = @()
                    procedureEdges = @()
                    methods = @()
                    lines = @()
                } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (
                    Join-Path $parameters.codeCoverageOutputPath 'coverage.bc.json'
                ) -Encoding UTF8
                $parameters.codeCoverageIsComplete = $true
                return $false
            }

            {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath `
                    -containerName 'test' -credential $testCredential `
                    -runTestsOverride $override -alToolPath 'C:\dotnet-tools\al.exe' `
                    -containerPlatformVersion '30.0.56026.0'
            } | Should -Throw '*There are test failures*'

            $status = Get-Content -LiteralPath (
                Join-Path (Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage') `
                    'coverage-status.json'
            ) -Raw -Encoding UTF8 | ConvertFrom-Json
            $status.runs[0].state | Should -Be 'complete'
            $coverageRoot = Join-Path (Join-Path $projectPath '.buildartifacts') 'CodeCoverage'
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $status.aggregate.format | Should -Be 'al-go-line-union-binary-gzip'
                Test-Path -LiteralPath (
                    Join-Path $coverageRoot 'coverage-aggregate.bin.gz'
                ) | Should -BeTrue
                @(Get-ChildItem -LiteralPath $coverageRoot `
                        -Filter 'coverage.bc.json' -File -Recurse).Count | Should -Be 0
            }
            else {
                @($status.PSObject.Properties.Name) | Should -Not -Contain 'aggregate'
                @(Get-ChildItem -LiteralPath $coverageRoot `
                        -Filter 'coverage.bc.json' -File -Recurse).Count | Should -Be 1
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }
    }

    Context 'Invoke-AlGoTestRun event log lifecycle' {
        It 'Captures after <Case>' -TestCases @(
            @{ Case = 'passing tests'; HasTestApp = $true; RunnerBehavior = 'Pass'; TreatAsWarning = $false; ExpectedError = $null; ExpectedRunnerCalls = 1 }
            @{ Case = 'a hard test failure'; HasTestApp = $true; RunnerBehavior = 'Fail'; TreatAsWarning = $false; ExpectedError = 'There are test failures'; ExpectedRunnerCalls = 1 }
            @{ Case = 'a warning-mode test failure'; HasTestApp = $true; RunnerBehavior = 'Fail'; TreatAsWarning = $true; ExpectedError = $null; ExpectedRunnerCalls = 1 }
            @{ Case = 'a no-test run'; HasTestApp = $false; RunnerBehavior = 'Pass'; TreatAsWarning = $false; ExpectedError = $null; ExpectedRunnerCalls = 0 }
            @{ Case = 'a runner exception'; HasTestApp = $true; RunnerBehavior = 'Throw'; TreatAsWarning = $false; ExpectedError = 'runner failed'; ExpectedRunnerCalls = 1 }
        ) {
            param($HasTestApp, $RunnerBehavior, $TreatAsWarning, $ExpectedError, $ExpectedRunnerCalls)

            Mock -ModuleName RunTests OutputWarning {}
            $compiledTestApps = if ($HasTestApp) { @('App1.Test.app') } else { @() }
            $projectPath = New-TestProject -CompiledTestApps $compiledTestApps
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            Set-Content -Path $eventLogDestination -Value 'pre-test-events' -Encoding UTF8
            $script:invocationOrder = @()
            $script:runnerCalls = 0
            $script:runnerBehavior = $RunnerBehavior
            $runTestsOverride = {
                param($parameters)
                $null = $parameters
                $script:runnerCalls++
                $script:invocationOrder += 'run'
                switch ($script:runnerBehavior) {
                    'Pass' { return $true }
                    'Fail' { return $false }
                    'Throw' { throw 'runner failed' }
                }
            }
            Mock -ModuleName RunTests Get-BcContainerEventLog {
                $script:invocationOrder += 'capture'
                return $script:eventLogSource
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $TreatAsWarning
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            $actualError = $null
            try {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride $runTestsOverride
            }
            catch {
                $actualError = $_.Exception.Message
            }

            if ($ExpectedError) {
                $actualError | Should -BeLike "*$ExpectedError*"
            }
            else {
                $actualError | Should -BeNullOrEmpty
            }
            $expectedOrder = if ($HasTestApp) { @('run', 'capture') } else { @('capture') }
            $script:invocationOrder | Should -Be $expectedOrder
            $script:runnerCalls | Should -Be $ExpectedRunnerCalls
            Should -Invoke -ModuleName RunTests Get-BcContainerEventLog -Times 1 -Exactly -ParameterFilter {
                $containerName -eq 'kept-container' -and $doNotOpen
            }
            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'post-test-events'
            Test-Path (Join-Path $projectPath 'TestResults.xml') | Should -BeFalse
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Warns and succeeds when event log capture fails after passing tests' {
            Mock -ModuleName RunTests OutputWarning {}
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $eventLogDestination = Join-Path $projectPath 'ContainerEventLog.evtx'
            Set-Content -Path $eventLogDestination -Value 'pre-test-events' -Encoding UTF8
            Mock -ModuleName RunTests Get-BcContainerEventLog { return (Join-Path $TestDrive 'missing.evtx') }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            { Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' -credential $testCredential -runTestsOverride { return $true } } |
                Should -Not -Throw

            (Get-Content -Path $eventLogDestination -Raw -Encoding UTF8).Trim() | Should -Be 'pre-test-events'
            Should -Invoke -ModuleName RunTests OutputWarning -Times 1 -Exactly -ParameterFilter {
                $message -like '*post-test container event log could not be captured*did not return a readable event log file*'
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }

        It 'Preserves <ExpectedError> when event log capture also fails' -TestCases @(
            @{ RunnerBehavior = 'Fail'; ExpectedError = 'There are test failures.' }
            @{ RunnerBehavior = 'Throw'; ExpectedError = 'runner failed' }
        ) {
            param($RunnerBehavior, $ExpectedError)

            Mock -ModuleName RunTests OutputWarning {}
            Mock -ModuleName RunTests Get-BcContainerEventLog { throw 'event export failed' }
            $projectPath = New-TestProject -CompiledTestApps @('App1.Test.app')
            $script:runnerBehavior = $RunnerBehavior
            $runTestsOverride = {
                if ($script:runnerBehavior -eq 'Throw') { throw 'runner failed' }
                return $false
            }
            $settings = @{
                doNotRunTests                  = $false
                runTestsInAllInstalledTestApps = $false
                companyName                    = ''
                treatTestFailuresAsWarnings    = $false
                testFolders                    = @(Get-TestFoldersForProject -ProjectPath $projectPath)
            }

            $actualError = $null
            try {
                Invoke-AlGoTestRun -settings $settings -projectPath $projectPath -containerName 'kept-container' `
                    -credential $testCredential -runTestsOverride $runTestsOverride
            }
            catch {
                $actualError = $_.Exception.Message
            }

            $actualError | Should -Be $ExpectedError
            Should -Invoke -ModuleName RunTests OutputWarning -Times 1 -Exactly -ParameterFilter {
                $message -like '*post-test container event log could not be captured*event export failed*'
            }
            Remove-Item -Path $projectPath -Recurse -Force
        }
    }
}
