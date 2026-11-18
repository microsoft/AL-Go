Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Deliver Module - Get-ProjectsInDeliveryOrder Tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        # Import the module in the same scope where AL-Go-Helper functions are available
        Import-Module (Join-Path $PSScriptRoot "../Actions/Deliver/Deliver.psm1" -Resolve) -DisableNameChecking -Scope Global
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'baseFolder', Justification = 'False positive.')]
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'returns empty array when no projects match selection' {
        $result = Get-ProjectsInDeliveryOrder -baseFolder $baseFolder -projectsFromSettings @() -selectProjects 'NonExistent*'
        $result | Should -BeExactly @()
    }

    It 'returns single project unchanged' {
        # Create a single project
        $appFile = @{
            id = '11111111-1111-1111-1111-111111111111'
            name = 'Single App'
            publisher = 'Contoso'
            version = '1.0.0.0'
            dependencies = @()
        }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appFile -Depth 10) -type File -Force

        $result = Get-ProjectsInDeliveryOrder -baseFolder $baseFolder -projectsFromSettings @() -selectProjects 'Project1'
        $result | Should -BeExactly @('Project1')
    }

    It 'sorts projects in linear dependency chain' {
        # Setup three projects with linear dependencies:
        # Project1 (base) - no dependencies
        # Project2 - depends on Project1
        # Project3 - depends on Project2

        # Create Project1 (base project)
        $baseAppFile = @{
            id = '11111111-1111-1111-1111-111111111111'
            name = 'Base App'
            publisher = 'Contoso'
            version = '1.0.0.0'
            dependencies = @()
        }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $baseAppFile -Depth 10) -type File -Force

        # Create Project2 (depends on Project1)
        $dependentApp1File = @{
            id = '22222222-2222-2222-2222-222222222222'
            name = 'Dependent App 1'
            publisher = 'Contoso'
            version = '1.0.0.0'
            dependencies = @(
                @{
                    id = '11111111-1111-1111-1111-111111111111'
                    name = 'Base App'
                    publisher = 'Contoso'
                    version = '1.0.0.0'
                }
            )
        }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependentApp1File -Depth 10) -type File -Force

        # Create Project3 (depends on Project2)
        $dependentApp2File = @{
            id = '33333333-3333-3333-3333-333333333333'
            name = 'Dependent App 2'
            publisher = 'Contoso'
            version = '1.0.0.0'
            dependencies = @(
                @{
                    id = '22222222-2222-2222-2222-222222222222'
                    name = 'Dependent App 1'
                    publisher = 'Contoso'
                    version = '1.0.0.0'
                }
            )
        }
        New-Item -Path "$baseFolder/Project3/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project3/app/app.json" -Value (ConvertTo-Json $dependentApp2File -Depth 10) -type File -Force

        # Set up AL-Go settings with useProjectDependencies enabled
        $alGoSettings = @{
            fullBuildPatterns = @()
            projects = @()
            powerPlatformSolutionFolder = ''
            useProjectDependencies = $true
        }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        # Call function - it will discover all projects and sort them
        $result = Get-ProjectsInDeliveryOrder -baseFolder $baseFolder -projectsFromSettings @() -selectProjects '*'

        # Verify correct dependency order
        $result.Count | Should -BeExactly 3
        $result[0] | Should -BeExactly 'Project1'
        $result[1] | Should -BeExactly 'Project2'
        $result[2] | Should -BeExactly 'Project3'
    }

    AfterEach {
        Remove-Item $baseFolder -Force -Recurse -ErrorAction SilentlyContinue
    }
}

Describe "Deliver Module - Get-AppSourceLibraryAppFile Tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())
        Import-Module (Join-Path $PSScriptRoot "../Actions/Deliver/Deliver.psm1" -Resolve) -Force -DisableNameChecking
    }

    BeforeEach {
        Mock Get-AppJsonFromAppFile -ModuleName Deliver {
            Param($appFile)

            switch ($appFile) {
                'Main.app' {
                    return @{ id = '11111111-1111-1111-1111-111111111111'; version = '2.0.0.0' }
                }
                'Main-Dependency.app' {
                    return @{ id = '11111111-1111-1111-1111-111111111111'; version = '3.0.0.0' }
                }
                'A.app' {
                    return @{
                        id = '22222222-2222-2222-2222-222222222222'
                        version = '1.0.0.0'
                        dependencies = @(@{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; version = '1.1.0.0' })
                    }
                }
                'X-Old.app' {
                    return @{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; version = '1.1.0.0' }
                }
                'X-New.app' {
                    return @{ id = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'; version = '1.2.0.0' }
                }
                'X-Renamed.app' {
                    return @{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; version = '1.10.0.0' }
                }
                'X-Copy.app' {
                    return @{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; version = '1.2.0.0' }
                }
                default {
                    throw "Unable to read app metadata from $appFile"
                }
            }
        }
    }

    It 'keeps only X 1.2 when A references X 1.1 and both X versions are included' -TestCases @(
        @{ appFiles = @('X-Old.app', 'A.app', 'X-New.app') }
        @{ appFiles = @('X-New.app', 'A.app', 'X-Old.app') }
    ) {
        Param($appFiles)

        $result = @(Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles $appFiles)

        $result | Should -BeExactly @('X-New.app', 'A.app')
    }

    It 'compares manifest versions numerically even when the package name changes' {
        $result = @(Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles @('X-New.app', 'X-Renamed.app'))

        $result | Should -BeExactly @('X-Renamed.app')
    }

    It 'keeps the first package when different paths contain the same app version' {
        $result = @(Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles @('X-New.app', 'X-Copy.app', 'X-New.app'))

        $result | Should -BeExactly @('X-New.app')
    }

    It 'excludes the main app ID from libraries without replacing the selected main package' {
        $result = @(Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles @('Main.app', 'A.app', 'Main-Dependency.app'))

        $result | Should -BeExactly @('A.app')
    }

    It 'preserves distinct library apps and their order' {
        $result = @(Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles @('A.app', 'X-New.app'))

        $result | Should -BeExactly @('A.app', 'X-New.app')
    }

    It 'returns no library files when none are included' {
        $result = @(Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles @())

        $result.Count | Should -Be 0
    }

    It 'propagates unreadable package errors instead of submitting an incomplete set of libraries' {
        { Get-AppSourceLibraryAppFile -appFile 'Main.app' -libraryAppFiles @('A.app', 'Corrupt.app') } |
            Should -Throw '*Unable to read app metadata from Corrupt.app*'
    }
}
