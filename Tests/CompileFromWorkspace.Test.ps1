$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/CompileFromWorkspace.psm1' -Resolve) -DisableNameChecking -Force

Describe 'CompileFromWorkspace.psm1 Tests' {
    BeforeAll {
        <#
        .SYNOPSIS
            Creates a realistic AL-Go project structure for testing.
        .DESCRIPTION
            Sets up a complete AL-Go project with .AL-Go/settings.json, app folders with app.json files,
            and test folders following the standard AL-Go conventions.

            The created folder structure mirrors a real AL-Go repository:

            BaseFolder/
            ├── .AL-Go/
            │   └── settings.json          # Contains country, appFolders, testFolders, bcptTestFolders
            ├── MyApp/                     # App folder (one per entry in AppFolders)
            │   └── app.json               # App manifest with id, name, publisher, version, dependencies, idRanges
            └── MyApp.Test/                # Test folder (one per entry in TestFolders)
                └── app.json               # Test app manifest

        .PARAMETER BaseFolder
            The root folder where the project structure will be created.
        .PARAMETER ProjectName
            Optional project name for multi-project repos. If empty, creates single-project structure at BaseFolder.
        .PARAMETER AppFolders
            Array of hashtables defining app folders. Each hashtable can have:
            - Name (required): Folder name for the app
            - Id: App GUID (auto-generated if not specified)
            - Publisher: Publisher name (defaults to "Test Publisher")
            - Version: App version (defaults to "1.0.0.0")
        .PARAMETER TestFolders
            Array of hashtables defining test folders. Same structure as AppFolders.
        .PARAMETER Settings
            Additional settings to merge into .AL-Go/settings.json.
        .OUTPUTS
            Returns the project path (BaseFolder or BaseFolder/ProjectName).
        .EXAMPLE
            # Create a simple single-app project
            $projectPath = New-ALGoTestProject -BaseFolder $TestDrive -AppFolders @(
                @{ Name = "MyApp"; Id = "11111111-1111-1111-1111-111111111111"; Version = "1.0.0.0" }
            )
        #>
        function script:New-ALGoTestProject {
            param(
                [Parameter(Mandatory = $true)]
                [string] $BaseFolder,
                [Parameter(Mandatory = $false)]
                [string] $ProjectName = "",
                [Parameter(Mandatory = $false)]
                [array] $AppFolders = @(),
                [Parameter(Mandatory = $false)]
                [array] $TestFolders = @(),
                [Parameter(Mandatory = $false)]
                [hashtable] $Settings = @{}
            )

            $projectPath = if ($ProjectName) { Join-Path $BaseFolder $ProjectName } else { $BaseFolder }
            $alGoFolder = Join-Path $projectPath ".AL-Go"

            New-Item -Path $alGoFolder -ItemType Directory -Force | Out-Null

            $defaultSettings = @{
                country = "us"
                appFolders = @($AppFolders | ForEach-Object { $_['Name'] })
                testFolders = @($TestFolders | ForEach-Object { $_['Name'] })
                bcptTestFolders = @()
            }

            foreach ($key in $Settings.Keys) {
                $defaultSettings[$key] = $Settings[$key]
            }

            $defaultSettings | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $alGoFolder "settings.json") -Encoding UTF8

            foreach ($app in $AppFolders) {
                $appFolder = Join-Path $projectPath $app['Name']
                New-Item -Path $appFolder -ItemType Directory -Force | Out-Null

                $appJson = @{
                    id = if ($app['Id']) { $app['Id'] } else { [guid]::NewGuid().ToString() }
                    name = $app['Name']
                    publisher = if ($app['Publisher']) { $app['Publisher'] } else { "Test Publisher" }
                    version = if ($app['Version']) { $app['Version'] } else { "1.0.0.0" }
                    dependencies = @()
                    platform = "1.0.0.0"
                    application = "22.0.0.0"
                    idRanges = @(@{ from = 50000; to = 50100 })
                }

                $appJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $appFolder "app.json") -Encoding UTF8
            }

            foreach ($testApp in $TestFolders) {
                $testFolder = Join-Path $projectPath $testApp['Name']
                New-Item -Path $testFolder -ItemType Directory -Force | Out-Null

                $testAppJson = @{
                    id = if ($testApp['Id']) { $testApp['Id'] } else { [guid]::NewGuid().ToString() }
                    name = $testApp['Name']
                    publisher = if ($testApp['Publisher']) { $testApp['Publisher'] } else { "Test Publisher" }
                    version = if ($testApp['Version']) { $testApp['Version'] } else { "1.0.0.0" }
                    dependencies = @()
                    platform = "1.0.0.0"
                    application = "22.0.0.0"
                    idRanges = @(@{ from = 60000; to = 60100 })
                }

                $testAppJson | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $testFolder "app.json") -Encoding UTF8
            }

            return $projectPath
        }
    }

    Describe 'Get-CodeAnalyzers' {
        It 'Returns empty array when no analyzers are enabled' {
            $settings = @{
                enableCodeCop = $false
                enableAppSourceCop = $false
                enablePerTenantExtensionCop = $false
                enableUICop = $false
            }

            $result = Get-CodeAnalyzers -Settings $settings

            @($result).Count | Should -Be 0
        }

        It 'Returns CodeCop when enableCodeCop is true' {
            $settings = @{
                enableCodeCop = $true
                enableAppSourceCop = $false
                enablePerTenantExtensionCop = $false
                enableUICop = $false
            }

            $result = Get-CodeAnalyzers -Settings $settings

            $result | Should -Contain 'CodeCop'
            @($result).Count | Should -Be 1
        }

        It 'Returns AppSourceCop when enableAppSourceCop is true' {
            $settings = @{
                enableCodeCop = $false
                enableAppSourceCop = $true
                enablePerTenantExtensionCop = $false
                enableUICop = $false
            }

            $result = Get-CodeAnalyzers -Settings $settings

            $result | Should -Contain 'AppSourceCop'
            @($result).Count | Should -Be 1
        }

        It 'Returns PTECop when enablePerTenantExtensionCop is true' {
            $settings = @{
                enableCodeCop = $false
                enableAppSourceCop = $false
                enablePerTenantExtensionCop = $true
                enableUICop = $false
            }

            $result = Get-CodeAnalyzers -Settings $settings

            $result | Should -Contain 'PTECop'
            @($result).Count | Should -Be 1
        }

        It 'Returns UICop when enableUICop is true' {
            $settings = @{
                enableCodeCop = $false
                enableAppSourceCop = $false
                enablePerTenantExtensionCop = $false
                enableUICop = $true
            }

            $result = Get-CodeAnalyzers -Settings $settings

            $result | Should -Contain 'UICop'
            @($result).Count | Should -Be 1
        }

        It 'Returns all analyzers when all are enabled' {
            $settings = @{
                enableCodeCop = $true
                enableAppSourceCop = $true
                enablePerTenantExtensionCop = $true
                enableUICop = $true
            }

            $result = Get-CodeAnalyzers -Settings $settings

            $result | Should -Contain 'CodeCop'
            $result | Should -Contain 'AppSourceCop'
            $result | Should -Contain 'PTECop'
            $result | Should -Contain 'UICop'
            @($result).Count | Should -Be 4
        }
    }

    Describe 'Get-BuildMetadata' {
        It 'Returns GitHub Actions metadata when running in GitHub Actions' {
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_SERVER_URL = 'https://github.com'
            $env:GITHUB_REPOSITORY = 'owner/repo'
            $env:GITHUB_SHA = 'def456'
            $env:GITHUB_RUN_ID = '12345'

            $result = Get-BuildMetadata

            $result.SourceRepositoryUrl | Should -Be 'https://github.com/owner/repo'
            $result.SourceCommit | Should -Be 'def456'
            $result.BuildBy | Should -Be 'AL-Go for GitHub'
            $result.BuildUrl | Should -Be 'https://github.com/owner/repo/actions/runs/12345'
        }

        AfterEach {
            $env:GITHUB_ACTIONS = $null
            $env:GITHUB_SERVER_URL = $null
            $env:GITHUB_REPOSITORY = $null
            $env:GITHUB_SHA = $null
            $env:GITHUB_RUN_ID = $null
        }
    }

    Describe 'Get-ScriptOverrides' {
        BeforeAll {
            # Get-ScriptOverrides is defined in AL-Go-Helper.ps1 (dot-sourced at file scope).
            # Re-dot-source here so it's available inside Pester's It blocks.
            . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
            # Trace-Information is from TelemetryHelper.psm1 which isn't loaded in tests
            function Trace-Information { param([string]$Message) }
        }

        It 'Returns empty hashtable when no override scripts exist' {
            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'no-overrides') -AppFolders @(
                @{ Name = "MyApp"; Id = "11111111-1111-1111-1111-111111111111" }
            )
            $alGoFolder = Join-Path $projectPath ".AL-Go"

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder -OverrideScriptNames @("PreCompileApp", "PostCompileApp")

            $result.Keys | Should -HaveCount 0
        }

        It 'Returns PreCompileApp override when script exists in .AL-Go folder' {
            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'precompile') -AppFolders @(
                @{ Name = "MyApp"; Id = "22222222-2222-2222-2222-222222222222" }
            )
            $alGoFolder = Join-Path $projectPath ".AL-Go"
            Set-Content -Path (Join-Path $alGoFolder 'PreCompileApp.ps1') -Value @'
Param(
    [ValidateSet('app','testApp')]
    [string] $appType,
    [ref] $compilationParams
)
Write-Host "Pre-compile for $appType"
'@

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder -OverrideScriptNames @("PreCompileApp", "PostCompileApp")

            $result.PreCompileApp | Should -Not -BeNullOrEmpty
            $result.Keys | Should -Not -Contain 'PostCompileApp'
        }

        It 'Returns PostCompileApp override when script exists in .AL-Go folder' {
            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'postcompile') -AppFolders @(
                @{ Name = "MyApp"; Id = "33333333-3333-3333-3333-333333333333" }
            )
            $alGoFolder = Join-Path $projectPath ".AL-Go"
            Set-Content -Path (Join-Path $alGoFolder 'PostCompileApp.ps1') -Value @'
Param(
    [string[]] $appFiles,
    [ValidateSet('app','testApp')]
    [string] $appType,
    [hashtable] $compilationParams
)
Write-Host "Post-compile: $($appFiles.Count) apps"
'@

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder -OverrideScriptNames @("PreCompileApp", "PostCompileApp")

            $result.Keys | Should -Not -Contain 'PreCompileApp'
            $result.PostCompileApp | Should -Not -BeNullOrEmpty
        }

        It 'Returns both overrides when both scripts exist in .AL-Go folder' {
            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'both-overrides') -AppFolders @(
                @{ Name = "MyApp"; Id = "44444444-4444-4444-4444-444444444444" }
            ) -TestFolders @(
                @{ Name = "MyApp.Test"; Id = "55555555-5555-5555-5555-555555555555" }
            )
            $alGoFolder = Join-Path $projectPath ".AL-Go"

            Set-Content -Path (Join-Path $alGoFolder 'PreCompileApp.ps1') -Value @'
Param(
    [ValidateSet('app','testApp')]
    [string] $appType,
    [ref] $compilationParams
)
Write-Host "Pre-compile for $appType"
'@
            Set-Content -Path (Join-Path $alGoFolder 'PostCompileApp.ps1') -Value @'
Param(
    [string[]] $appFiles,
    [ValidateSet('app','testApp')]
    [string] $appType,
    [hashtable] $compilationParams
)
Write-Host "Post-compile: $($appFiles.Count) apps"
'@

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder -OverrideScriptNames @("PreCompileApp", "PostCompileApp")

            $result.Keys | Should -Contain 'PreCompileApp'
            $result.Keys | Should -Contain 'PostCompileApp'
        }
    }

    Describe 'Update-AppJsonProperties' {
        It 'Updates version with MajorMinorVersion, BuildNumber and RevisionNumber' {
            $projectPath = New-ALGoTestProject -BaseFolder $TestDrive -AppFolders @(
                @{ Name = "MyApp"; Id = "11111111-1111-1111-1111-111111111111"; Version = "1.0.0.0" }
            )
            $appFolder = Join-Path $projectPath "MyApp"

            Update-AppJsonProperties -Folders @($appFolder) -MajorMinorVersion "2.5" -BuildNumber 100 -RevisionNumber 50

            $updatedAppJson = Get-Content -Path (Join-Path $appFolder 'app.json') | ConvertFrom-Json
            $updatedAppJson.version | Should -Be '2.5.100.50'
        }

        It 'Updates only BuildNumber and RevisionNumber when MajorMinorVersion is not provided' {
            $projectPath = New-ALGoTestProject -BaseFolder $TestDrive -AppFolders @(
                @{ Name = "MyApp2"; Id = "22222222-2222-2222-2222-222222222222"; Version = "1.0.0.0" }
            )
            $appFolder = Join-Path $projectPath "MyApp2"

            Update-AppJsonProperties -Folders @($appFolder) -BuildNumber 200 -RevisionNumber 75

            $updatedAppJson = Get-Content -Path (Join-Path $appFolder 'app.json') | ConvertFrom-Json
            $updatedAppJson.version | Should -Be '1.0.200.75'
        }

        It 'Updates only RevisionNumber when BuildNumber is 0' {
            $projectPath = New-ALGoTestProject -BaseFolder $TestDrive -AppFolders @(
                @{ Name = "MyApp3"; Id = "33333333-3333-3333-3333-333333333333"; Version = "1.0.0.0" }
            )
            $appFolder = Join-Path $projectPath "MyApp3"

            Update-AppJsonProperties -Folders @($appFolder) -RevisionNumber 99

            $updatedAppJson = Get-Content -Path (Join-Path $appFolder 'app.json') | ConvertFrom-Json
            $updatedAppJson.version | Should -Be '1.0.0.99'
        }

        It 'Updates multiple app folders in a project' {
            $projectPath = New-ALGoTestProject -BaseFolder $TestDrive -AppFolders @(
                @{ Name = "App1"; Id = "44444444-4444-4444-4444-444444444444"; Version = "1.0.0.0" }
                @{ Name = "App2"; Id = "55555555-5555-5555-5555-555555555555"; Version = "2.0.0.0" }
            )
            $appFolders = @(
                (Join-Path $projectPath "App1"),
                (Join-Path $projectPath "App2")
            )

            Update-AppJsonProperties -Folders $appFolders -MajorMinorVersion "3.0" -BuildNumber 50 -RevisionNumber 10

            $app1Json = Get-Content -Path (Join-Path $projectPath "App1\app.json") | ConvertFrom-Json
            $app2Json = Get-Content -Path (Join-Path $projectPath "App2\app.json") | ConvertFrom-Json

            $app1Json.version | Should -Be '3.0.50.10'
            $app2Json.version | Should -Be '3.0.50.10'
        }

        It 'Updates app and test folders together' {
            $projectPath = New-ALGoTestProject -BaseFolder $TestDrive `
                -AppFolders @(
                    @{ Name = "MainApp"; Id = "66666666-6666-6666-6666-666666666666"; Version = "1.0.0.0" }
                ) `
                -TestFolders @(
                    @{ Name = "MainApp.Test"; Id = "77777777-7777-7777-7777-777777777777"; Version = "1.0.0.0" }
                )

            $allFolders = @(
                (Join-Path $projectPath "MainApp"),
                (Join-Path $projectPath "MainApp.Test")
            )

            Update-AppJsonProperties -Folders $allFolders -MajorMinorVersion "4.0" -BuildNumber 123 -RevisionNumber 456

            $appJson = Get-Content -Path (Join-Path $projectPath "MainApp\app.json") | ConvertFrom-Json
            $testJson = Get-Content -Path (Join-Path $projectPath "MainApp.Test\app.json") | ConvertFrom-Json

            $appJson.version | Should -Be '4.0.123.456'
            $testJson.version | Should -Be '4.0.123.456'
        }
    }

    Describe 'Build-AppsInWorkspace' {
        BeforeAll {
            # Create a mock compiler folder structure
            $script:mockCompilerFolder = Join-Path $TestDrive 'compiler'
            New-Item -Path $script:mockCompilerFolder -ItemType Directory -Force | Out-Null

            # Create a fake altool executable
            $altoolPath = Join-Path $script:mockCompilerFolder 'altool.exe'
            Set-Content -Path $altoolPath -Value "mock"
        }

        It 'Uses default PackageCachePath when not specified' {
            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace {
                param($ALToolPath, $WorkspaceFile, $PackageCachePath, $OutFolder)
                # Verify PackageCachePath defaults to compiler\symbols
                $PackageCachePath | Should -BeLike '*compiler*symbols'
                return @()
            } -ModuleName CompileFromWorkspace

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj1') -AppFolders @(
                @{ Name = "App1"; Id = "11111111-1111-1111-1111-111111111111" }
            )

            Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App1")) -CompilerFolder $script:mockCompilerFolder
        }

        It 'Uses specified PackageCachePath when provided' {
            $customCachePath = Join-Path $TestDrive 'custom-cache'
            New-Item -Path $customCachePath -ItemType Directory -Force | Out-Null

            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace {
                param($ALToolPath, $WorkspaceFile, $PackageCachePath, $OutFolder)
                $PackageCachePath | Should -Be $customCachePath
                return @()
            } -ModuleName CompileFromWorkspace -ParameterFilter { $PackageCachePath -eq $customCachePath }

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj2') -AppFolders @(
                @{ Name = "App2"; Id = "22222222-2222-2222-2222-222222222222" }
            )

            Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App2")) -CompilerFolder $script:mockCompilerFolder -PackageCachePath $customCachePath
        }

        It 'Caps MaxCpuCount to available processor count' {
            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace {
                param($ALToolPath, $WorkspaceFile, $PackageCachePath, $OutFolder, $AssemblyProbingPaths, $Analyzers, $PreprocessorSymbols, $Features, $GenerateReportLayout, $Ruleset, $SourceRepositoryUrl, $SourceCommit, $BuildBy, $BuildUrl, $ReportSuppressedDiagnostics, $EnableExternalRulesets, $MaxCpuCount)
                # MaxCpuCount should be capped to processor count
                $MaxCpuCount | Should -BeLessOrEqual ([System.Environment]::ProcessorCount)
                return @()
            } -ModuleName CompileFromWorkspace

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj3') -AppFolders @(
                @{ Name = "App3"; Id = "33333333-3333-3333-3333-333333333333" }
            )

            Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App3")) -CompilerFolder $script:mockCompilerFolder -MaxCpuCount 9999
        }

        It 'Invokes PreCompileApp script before compilation' {
            $script:preCompileInvoked = $false

            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace { return @() } -ModuleName CompileFromWorkspace

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj4') -AppFolders @(
                @{ Name = "App4"; Id = "44444444-4444-4444-4444-444444444444" }
            )

            $preCompileScript = {
                param($appType, $compilationParams)
                $script:preCompileInvoked = $true
            }

            Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App4")) -CompilerFolder $script:mockCompilerFolder -PreCompileApp $preCompileScript -AppType 'app'

            $script:preCompileInvoked | Should -Be $true
        }

        It 'Invokes PostCompileApp script after compilation' {
            $script:postCompileInvoked = $false

            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace { return @('app1.app', 'app2.app') } -ModuleName CompileFromWorkspace

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj5') -AppFolders @(
                @{ Name = "App5"; Id = "55555555-5555-5555-5555-555555555555" }
            )

            $postCompileScript = {
                param($appFiles, $appType, $compilationParams)
                $script:postCompileInvoked = $true
                @($appFiles).Count | Should -Be 2
            }

            Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App5")) -CompilerFolder $script:mockCompilerFolder -PostCompileApp $postCompileScript -AppType 'app'

            $script:postCompileInvoked | Should -Be $true
        }

        It 'Returns compiled app files from CompileAppsInWorkspace' {
            $expectedApps = @('MyApp_1.0.0.0.app', 'MyApp2_1.0.0.0.app')

            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace { return $expectedApps } -ModuleName CompileFromWorkspace

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj6') -AppFolders @(
                @{ Name = "App6"; Id = "66666666-6666-6666-6666-666666666666" }
            )

            $result = Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App6")) -CompilerFolder $script:mockCompilerFolder

            @($result).Count | Should -Be 2
            $result | Should -Contain 'MyApp_1.0.0.0.app'
            $result | Should -Contain 'MyApp2_1.0.0.0.app'
        }

        It 'Passes analyzers to CompileAppsInWorkspace' {
            Mock Get-ALTool { return (Join-Path $TestDrive 'compiler\altool.exe') } -ModuleName CompileFromWorkspace
            Mock New-WorkspaceFromFolders { } -ModuleName CompileFromWorkspace
            Mock CompileAppsInWorkspace {
                param($ALToolPath, $WorkspaceFile, $PackageCachePath, $OutFolder, $AssemblyProbingPaths, $Analyzers)
                $Analyzers | Should -Contain 'CodeCop'
                $Analyzers | Should -Contain 'UICop'
                return @()
            } -ModuleName CompileFromWorkspace

            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'proj7') -AppFolders @(
                @{ Name = "App7"; Id = "77777777-7777-7777-7777-777777777777" }
            )

            Build-AppsInWorkspace -Folders @((Join-Path $projectPath "App7")) -CompilerFolder $script:mockCompilerFolder -Analyzers @('CodeCop', 'UICop')
        }
    }

    Describe 'Copy-CompiledAppsToOutput' {
        It 'Returns new files that appeared after compilation' {
            InModuleScope CompileFromWorkspace {
                $packageCache = Join-Path $TestDrive 'cache-copy1'
                $outputFolder = Join-Path $TestDrive 'output-copy1'
                New-Item -Path $packageCache -ItemType Directory -Force | Out-Null

                $filesBefore = @{}

                $appFile = Join-Path $packageCache 'NewApp_1.0.0.0.app'
                Set-Content -Path $appFile -Value 'compiled'

                $result = @(Copy-CompiledAppsToOutput -PackageCachePath $packageCache -OutputFolder $outputFolder -FilesBeforeCompile $filesBefore)

                $result.Count | Should -Be 1
                $result[0] | Should -BeLike '*NewApp_1.0.0.0.app'
                Test-Path (Join-Path $outputFolder 'NewApp_1.0.0.0.app') | Should -Be $true
            }
        }

        It 'Returns modified files with newer timestamps' {
            InModuleScope CompileFromWorkspace {
                $packageCache = Join-Path $TestDrive 'cache-copy2'
                $outputFolder = Join-Path $TestDrive 'output-copy2'
                New-Item -Path $packageCache -ItemType Directory -Force | Out-Null

                $appFile = Join-Path $packageCache 'Existing_1.0.0.0.app'
                Set-Content -Path $appFile -Value 'old'
                $oldTimestamp = (Get-Item $appFile).LastWriteTimeUtc

                $filesBefore = @{ $appFile = $oldTimestamp }

                Start-Sleep -Milliseconds 100
                Set-Content -Path $appFile -Value 'recompiled'

                $result = Copy-CompiledAppsToOutput -PackageCachePath $packageCache -OutputFolder $outputFolder -FilesBeforeCompile $filesBefore

                @($result).Count | Should -Be 1
            }
        }

        It 'Skips unchanged files' {
            InModuleScope CompileFromWorkspace {
                $packageCache = Join-Path $TestDrive 'cache-copy3'
                $outputFolder = Join-Path $TestDrive 'output-copy3'
                New-Item -Path $packageCache -ItemType Directory -Force | Out-Null

                $appFile = Join-Path $packageCache 'Unchanged_1.0.0.0.app'
                Set-Content -Path $appFile -Value 'content'
                $timestamp = (Get-Item $appFile).LastWriteTimeUtc

                $filesBefore = @{ $appFile = $timestamp }

                $result = Copy-CompiledAppsToOutput -PackageCachePath $packageCache -OutputFolder $outputFolder -FilesBeforeCompile $filesBefore

                @($result).Count | Should -Be 0
            }
        }

        It 'Skips copy when PackageCachePath equals OutputFolder' {
            InModuleScope CompileFromWorkspace {
                $sameFolder = Join-Path $TestDrive 'cache-copy4'
                New-Item -Path $sameFolder -ItemType Directory -Force | Out-Null

                $appFile = Join-Path $sameFolder 'App_1.0.0.0.app'
                Set-Content -Path $appFile -Value 'compiled'

                $result = Copy-CompiledAppsToOutput -PackageCachePath $sameFolder -OutputFolder $sameFolder -FilesBeforeCompile @{}

                @($result).Count | Should -Be 1
                Test-Path $appFile | Should -Be $true
            }
        }

        It 'Creates OutputFolder if it does not exist' {
            InModuleScope CompileFromWorkspace {
                $packageCache = Join-Path $TestDrive 'cache-copy5'
                $outputFolder = Join-Path $TestDrive 'output-copy5-new'
                New-Item -Path $packageCache -ItemType Directory -Force | Out-Null

                $appFile = Join-Path $packageCache 'App_1.0.0.0.app'
                Set-Content -Path $appFile -Value 'compiled'

                Test-Path $outputFolder | Should -Be $false

                Copy-CompiledAppsToOutput -PackageCachePath $packageCache -OutputFolder $outputFolder -FilesBeforeCompile @{}

                Test-Path $outputFolder | Should -Be $true
            }
        }
    }

    Describe 'New-BuildOutputFile' {
        It 'Creates build output file from log files' {
            $buildArtifactFolder = Join-Path $TestDrive 'artifacts-build1'
            $logsFolder = Join-Path $buildArtifactFolder 'Logs'
            New-Item -Path $logsFolder -ItemType Directory -Force | Out-Null

            # Create a mock log file
            Set-Content -Path (Join-Path $logsFolder 'compile.log') -Value "[OUT] warning AL0001: Some warning`n[OUT] info AL0002: Some info"

            $outputPath = Join-Path $TestDrive 'BuildOutput1.txt'

            Mock Convert-AlcOutputToAzureDevOps { } -ModuleName CompileFromWorkspace

            $result = New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath $outputPath

            $result | Should -Be $outputPath
            Test-Path $outputPath | Should -Be $true
            $content = Get-Content $outputPath
            $content | Should -Contain 'warning AL0001: Some warning'
        }

        It 'Strips [OUT] prefix from log lines' {
            $buildArtifactFolder = Join-Path $TestDrive 'artifacts-build2'
            $logsFolder = Join-Path $buildArtifactFolder 'Logs'
            New-Item -Path $logsFolder -ItemType Directory -Force | Out-Null

            Set-Content -Path (Join-Path $logsFolder 'compile.log') -Value "[OUT] some output line"

            $outputPath = Join-Path $TestDrive 'BuildOutput2.txt'

            Mock Convert-AlcOutputToAzureDevOps { } -ModuleName CompileFromWorkspace

            New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath $outputPath

            $content = Get-Content $outputPath
            $content | Should -Contain 'some output line'
            $content | Should -Not -Contain '[OUT] some output line'
        }

        It 'Handles empty artifacts folder with no log files' {
            $buildArtifactFolder = Join-Path $TestDrive 'artifacts-build3'
            New-Item -Path $buildArtifactFolder -ItemType Directory -Force | Out-Null

            $outputPath = Join-Path $TestDrive 'BuildOutput3.txt'

            $result = New-BuildOutputFile -BuildArtifactFolder $buildArtifactFolder -BuildOutputPath $outputPath

            $result | Should -Be $outputPath
            Test-Path $outputPath | Should -Be $true
        }
    }

    Describe 'Get-CustomAnalyzers' {
        It 'Returns empty array when no custom code cops configured' {
            $result = Get-CustomAnalyzers -Settings @{ CustomCodeCops = @() } -CompilerFolder $TestDrive

            @($result).Count | Should -Be 0
        }

        It 'Returns local paths as-is' {
            $result = Get-CustomAnalyzers -Settings @{ CustomCodeCops = @('C:\analyzers\MyAnalyzer.dll') } -CompilerFolder $TestDrive

            @($result).Count | Should -Be 1
            $result | Should -Contain 'C:\analyzers\MyAnalyzer.dll'
        }

        It 'Downloads URL-based analyzers to compiler folder' {
            $compilerFolder = Join-Path $TestDrive 'compiler-analyzers'
            $analyzersBin = Join-Path $compilerFolder 'compiler\extension\bin\Analyzers'
            New-Item -Path $analyzersBin -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'mock-dll'
            } -ModuleName CompileFromWorkspace

            $result = @(Get-CustomAnalyzers -Settings @{ CustomCodeCops = @('https://example.com/MyAnalyzer.dll') } -CompilerFolder $compilerFolder)

            $result.Count | Should -Be 1
            $result[0] | Should -BeLike '*MyAnalyzer.dll'
        }
    }

    Describe 'Get-AssemblyProbingPaths' {
        It 'Includes Service and Mock Assemblies when dlls folder exists' {
            $compilerFolder = Join-Path $TestDrive 'compiler-probing1'
            $dllsPath = Join-Path $compilerFolder 'dlls'
            New-Item -Path (Join-Path $dllsPath 'Service') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $dllsPath 'Mock Assemblies') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $dllsPath 'OpenXML') -ItemType Directory -Force | Out-Null

            Mock Get-DotnetRuntimeVersionInstalled { return $null } -ModuleName CompileFromWorkspace

            $result = Get-AssemblyProbingPaths -CompilerFolder $compilerFolder

            ($result -like '*Service') | Should -Not -BeNullOrEmpty
            ($result -like '*Mock Assemblies') | Should -Not -BeNullOrEmpty
            ($result -like '*OpenXML') | Should -Not -BeNullOrEmpty
        }

        It 'Uses shared folder when it exists' {
            $compilerFolder = Join-Path $TestDrive 'compiler-probing2'
            $dllsPath = Join-Path $compilerFolder 'dlls'
            $sharedPath = Join-Path $dllsPath 'shared'
            New-Item -Path $sharedPath -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $dllsPath 'OpenXML') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $dllsPath 'Service') -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $dllsPath 'Mock Assemblies') -ItemType Directory -Force | Out-Null

            $result = Get-AssemblyProbingPaths -CompilerFolder $compilerFolder

            ($result -like '*shared') | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'CompileAppsInWorkspace argument construction' {
        It 'Includes --analyzers when analyzers are specified' {
            InModuleScope CompileFromWorkspace {
                $script:capturedArguments = @()
                $wsFile = Join-Path $TestDrive 'test.code-workspace'
                Set-Content -Path $wsFile -Value '{}'
                $outDir = Join-Path $TestDrive 'out-args1'
                New-Item -Path $outDir -ItemType Directory -Force | Out-Null
                Mock RunAndCheck {
                    $script:capturedArguments = $args
                }
                Mock Copy-CompiledAppsToOutput { return @() }

                CompileAppsInWorkspace -ALToolPath 'altool.exe' -WorkspaceFile $wsFile -MaxCpuCount 1 -OutFolder $outDir -PackageCachePath $outDir -Analyzers @('CodeCop', 'UICop')

                $script:capturedArguments | Should -Contain '--analyzers'
                $script:capturedArguments | Should -Contain 'CodeCop,UICop'
            }
        }

        It 'Includes --features when features are specified' {
            InModuleScope CompileFromWorkspace {
                $script:capturedArguments = @()
                $wsFile = Join-Path $TestDrive 'test.code-workspace'
                Set-Content -Path $wsFile -Value '{}'
                $outDir = Join-Path $TestDrive 'out-args2'
                New-Item -Path $outDir -ItemType Directory -Force | Out-Null
                Mock RunAndCheck {
                    $script:capturedArguments = $args
                }
                Mock Copy-CompiledAppsToOutput { return @() }

                CompileAppsInWorkspace -ALToolPath 'altool.exe' -WorkspaceFile $wsFile -MaxCpuCount 1 -OutFolder $outDir -PackageCachePath $outDir -Features @('TranslationFile', 'GenerateCaptions')

                $script:capturedArguments | Should -Contain '--features'
                $script:capturedArguments | Should -Contain 'TranslationFile,GenerateCaptions'
            }
        }

        It 'Includes --define when preprocessor symbols are specified' {
            InModuleScope CompileFromWorkspace {
                $script:capturedArguments = @()
                $wsFile = Join-Path $TestDrive 'test.code-workspace'
                Set-Content -Path $wsFile -Value '{}'
                $outDir = Join-Path $TestDrive 'out-args3'
                New-Item -Path $outDir -ItemType Directory -Force | Out-Null
                Mock RunAndCheck {
                    $script:capturedArguments = $args
                }
                Mock Copy-CompiledAppsToOutput { return @() }

                CompileAppsInWorkspace -ALToolPath 'altool.exe' -WorkspaceFile $wsFile -MaxCpuCount 1 -OutFolder $outDir -PackageCachePath $outDir -PreprocessorSymbols @('CLEAN', 'DEBUG')

                $script:capturedArguments | Should -Contain '--define'
                $script:capturedArguments | Should -Contain 'CLEAN;DEBUG'
            }
        }

        It 'Includes --ruleset when ruleset is specified' {
            InModuleScope CompileFromWorkspace {
                $script:capturedArguments = @()
                $wsFile = Join-Path $TestDrive 'test.code-workspace'
                Set-Content -Path $wsFile -Value '{}'
                $outDir = Join-Path $TestDrive 'out-args4'
                New-Item -Path $outDir -ItemType Directory -Force | Out-Null
                Mock RunAndCheck {
                    $script:capturedArguments = $args
                }
                Mock Copy-CompiledAppsToOutput { return @() }

                CompileAppsInWorkspace -ALToolPath 'altool.exe' -WorkspaceFile $wsFile -MaxCpuCount 1 -OutFolder $outDir -PackageCachePath $outDir -Ruleset 'myruleset.json'

                $script:capturedArguments | Should -Contain '--ruleset'
                $script:capturedArguments | Should -Contain 'myruleset.json'
            }
        }

        It 'Omits --maxcpucount when equal to processor count' {
            InModuleScope CompileFromWorkspace {
                $script:capturedArguments = @()
                $wsFile = Join-Path $TestDrive 'test.code-workspace'
                Set-Content -Path $wsFile -Value '{}'
                $outDir = Join-Path $TestDrive 'out-args5'
                New-Item -Path $outDir -ItemType Directory -Force | Out-Null
                Mock RunAndCheck {
                    $script:capturedArguments = $args
                }
                Mock Copy-CompiledAppsToOutput { return @() }

                CompileAppsInWorkspace -ALToolPath 'altool.exe' -WorkspaceFile $wsFile -MaxCpuCount ([System.Environment]::ProcessorCount) -OutFolder $outDir -PackageCachePath $outDir

                $script:capturedArguments | Should -Not -Contain '--maxcpucount'
            }
        }

        It 'Always includes --logdirectory' {
            InModuleScope CompileFromWorkspace {
                $script:capturedArguments = @()
                $wsFile = Join-Path $TestDrive 'test.code-workspace'
                Set-Content -Path $wsFile -Value '{}'
                $outDir = Join-Path $TestDrive 'out-args6'
                New-Item -Path $outDir -ItemType Directory -Force | Out-Null
                Mock RunAndCheck {
                    $script:capturedArguments = $args
                }
                Mock Copy-CompiledAppsToOutput { return @() }

                CompileAppsInWorkspace -ALToolPath 'altool.exe' -WorkspaceFile $wsFile -MaxCpuCount 1 -OutFolder $outDir -PackageCachePath $outDir

                $script:capturedArguments | Should -Contain '--logdirectory'
            }
        }
    }

    Describe 'New-AppSourceCopJson' {
        BeforeEach {
            # Create app folders with app.json
            $script:appFolder = Join-Path $TestDrive "MyApp"
            New-Item -Path $script:appFolder -ItemType Directory -Force | Out-Null
            @{
                id = "11111111-1111-1111-1111-111111111111"
                name = "MyApp"
                publisher = "Contoso"
                version = "2.0.0.0"
            } | ConvertTo-Json | Set-Content (Join-Path $script:appFolder "app.json")

            # Mock the AL tool to return manifest info from previous apps
            Mock Get-ALTool { return "altool.exe" } -ModuleName CompileFromWorkspace
            Mock RunAndCheck {
                return '{"Publisher":"Contoso","Name":"MyApp","Version":"1.0.0.0"}'
            } -ModuleName CompileFromWorkspace
        }

        It 'Creates AppSourceCop.json with baseline version from previous app' {
            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings @{
                appSourceCopMandatoryAffixes = @()
                obsoleteTagMinAllowedMajorMinor = ""
            }

            $result = Get-Content (Join-Path $script:appFolder "AppSourceCop.json") -Raw | ConvertFrom-Json
            $result.Publisher | Should -Be "Contoso"
            $result.Name | Should -Be "MyApp"
            $result.Version | Should -Be "1.0.0.0"
        }

        It 'Includes mandatory affixes from settings' {
            $settings = @{
                appSourceCopMandatoryAffixes = @("Test", "Contoso")
                obsoleteTagMinAllowedMajorMinor = ""
            }

            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings $settings

            $result = Get-Content (Join-Path $script:appFolder "AppSourceCop.json") -Raw | ConvertFrom-Json
            $result.mandatoryAffixes | Should -Be @("Test", "Contoso")
        }

        It 'Includes obsoleteTagMinAllowedMajorMinor from settings' {
            $settings = @{
                appSourceCopMandatoryAffixes = @()
                obsoleteTagMinAllowedMajorMinor = "24.0"
            }

            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings $settings

            $result = Get-Content (Join-Path $script:appFolder "AppSourceCop.json") -Raw | ConvertFrom-Json
            $result.obsoleteTagMinAllowedMajorMinor | Should -Be "24.0"
        }

        It 'Combines settings and baseline version in one file' {
            $settings = @{
                appSourceCopMandatoryAffixes = @("Test")
                obsoleteTagMinAllowedMajorMinor = "23.0"
            }

            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings $settings

            $result = Get-Content (Join-Path $script:appFolder "AppSourceCop.json") -Raw | ConvertFrom-Json
            $result.Publisher | Should -Be "Contoso"
            $result.Version | Should -Be "1.0.0.0"
            $result.mandatoryAffixes | Should -Be @("Test")
            $result.obsoleteTagMinAllowedMajorMinor | Should -Be "23.0"
        }

        It 'Does not create file when no previous app matches and no settings apply' {
            Mock RunAndCheck {
                return '{"Publisher":"OtherPublisher","Name":"OtherApp","Version":"1.0.0.0"}'
            } -ModuleName CompileFromWorkspace

            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings @{
                appSourceCopMandatoryAffixes = @()
                obsoleteTagMinAllowedMajorMinor = ""
            }

            Test-Path (Join-Path $script:appFolder "AppSourceCop.json") | Should -Be $false
        }

        It 'Removes existing AppSourceCop.json when nothing to write' {
            # Pre-create an AppSourceCop.json
            $copJsonPath = Join-Path $script:appFolder "AppSourceCop.json"
            '{"old":"content"}' | Set-Content $copJsonPath

            Mock RunAndCheck {
                return '{"Publisher":"OtherPublisher","Name":"OtherApp","Version":"1.0.0.0"}'
            } -ModuleName CompileFromWorkspace

            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings @{
                appSourceCopMandatoryAffixes = @()
                obsoleteTagMinAllowedMajorMinor = ""
            }

            Test-Path $copJsonPath | Should -Be $false
        }

        It 'Handles multiple app folders, only writing for matching ones' {
            $appFolder2 = Join-Path $TestDrive "OtherApp"
            New-Item -Path $appFolder2 -ItemType Directory -Force | Out-Null
            @{
                id = "22222222-2222-2222-2222-222222222222"
                name = "OtherApp"
                publisher = "OtherPublisher"
                version = "1.0.0.0"
            } | ConvertTo-Json | Set-Content (Join-Path $appFolder2 "app.json")

            # RunAndCheck only returns a match for MyApp/Contoso
            New-AppSourceCopJson -AppFolders @($script:appFolder, $appFolder2) -PreviousApps @("dummy.app") -CompilerFolder "c:\compiler" -Settings @{
                appSourceCopMandatoryAffixes = @()
                obsoleteTagMinAllowedMajorMinor = ""
            }

            # MyApp should have AppSourceCop.json (publisher/name match)
            Test-Path (Join-Path $script:appFolder "AppSourceCop.json") | Should -Be $true
            # OtherApp should not (no match from RunAndCheck mock)
            Test-Path (Join-Path $appFolder2 "AppSourceCop.json") | Should -Be $false
        }

        It 'Warns and continues when reading manifest fails' {
            Mock RunAndCheck { throw "Failed to read app" } -ModuleName CompileFromWorkspace
            Mock OutputWarning {} -ModuleName CompileFromWorkspace

            New-AppSourceCopJson -AppFolders @($script:appFolder) -PreviousApps @("bad.app") -CompilerFolder "c:\compiler" -Settings @{
                appSourceCopMandatoryAffixes = @("Test")
                obsoleteTagMinAllowedMajorMinor = ""
            }

            # Should still create the file with just the affixes
            $result = Get-Content (Join-Path $script:appFolder "AppSourceCop.json") -Raw | ConvertFrom-Json
            $result.mandatoryAffixes | Should -Be @("Test")
            Should -Invoke OutputWarning -ModuleName CompileFromWorkspace -Times 1
        }
    }
}
