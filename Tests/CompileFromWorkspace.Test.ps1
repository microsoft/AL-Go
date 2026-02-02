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
        It 'Returns local build metadata when not running in GitHub Actions' {
            $env:GITHUB_ACTIONS = $null

            $result = Get-BuildMetadata

            $result.BuildBy | Should -Be 'AL-Go for GitHub (local)'
            $result.BuildUrl | Should -Be 'N/A'
        }

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
        It 'Returns null overrides when no override scripts exist' {
            $projectPath = New-ALGoTestProject -BaseFolder (Join-Path $TestDrive 'no-overrides') -AppFolders @(
                @{ Name = "MyApp"; Id = "11111111-1111-1111-1111-111111111111" }
            )
            $alGoFolder = Join-Path $projectPath ".AL-Go"

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder

            $result.PreCompileApp | Should -BeNullOrEmpty
            $result.PostCompileApp | Should -BeNullOrEmpty
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

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder

            $result.PreCompileApp | Should -Not -BeNullOrEmpty
            $result.PostCompileApp | Should -BeNullOrEmpty
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

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder

            $result.PreCompileApp | Should -BeNullOrEmpty
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

            $result = Get-ScriptOverrides -ALGoFolderName $alGoFolder

            $result.PreCompileApp | Should -Not -BeNullOrEmpty
            $result.PostCompileApp | Should -Not -BeNullOrEmpty
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
}
