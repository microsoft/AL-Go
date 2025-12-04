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

        # Verify that Project1 comes before Project2 and Project3
        $project1Index = [array]::IndexOf($result, 'Project1')
        $project2Index = [array]::IndexOf($result, 'Project2')
        $project3Index = [array]::IndexOf($result, 'Project3')

        $project1Index | Should -BeLessThan $project2Index
        $project2Index | Should -BeLessThan $project3Index
    }

    AfterEach {
        Remove-Item $baseFolder -Force -Recurse -ErrorAction SilentlyContinue
    }
}
