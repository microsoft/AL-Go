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

Describe "Deliver Module - Get-ArtifactsForDelivery Tests" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        Import-Module (Join-Path $PSScriptRoot "../Actions/Deliver/Deliver.psm1" -Resolve) -DisableNameChecking -Scope Global

        $ENV:GITHUB_API_URL = 'https://api.github.com'
        $ENV:GITHUB_REPOSITORY = 'myOrg/myRepo'
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'artifactsFolder', Justification = 'False positive.')]
        $artifactsFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName

        # Do not unpack/delete anything - the artifacts are never really downloaded in these tests
        Mock Test-Path { return $true } -ModuleName Deliver
        Mock Expand-Archive { } -ModuleName Deliver
        Mock Remove-Item { } -ModuleName Deliver
        Mock DownloadRelease { return (Join-Path $artifactsFolder 'MyProject-main-Apps-1.0.0.0.zip') } -ModuleName Deliver
        Mock DownloadArtifact { return (Join-Path $artifactsFolder 'MyProject-main-Apps-1.0.0.0.zip') } -ModuleName Deliver
        Mock GetArtifacts { return @([PSCustomObject]@{ Name = 'MyProject-main-Apps-1.0.0.0' }) } -ModuleName Deliver
    }

    It 'does nothing when the artifacts have already been downloaded' {
        Mock GetReleases { throw 'GetReleases should not be called' } -ModuleName Deliver

        Get-ArtifactsForDelivery -token 'token' -artifacts '.artifacts' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps' -branch 'main' | Should -BeExactly 'MyProject'

        Should -Invoke GetArtifacts -ModuleName Deliver -Times 0 -Exactly
        Should -Invoke DownloadRelease -ModuleName Deliver -Times 0 -Exactly
    }

    It 'downloads artifacts from the current release when releases exist' {
        Mock GetReleases {
            return @([PSCustomObject]@{ tag_name = '1.0.0'; prerelease = $false; draft = $false })
        } -ModuleName Deliver

        Get-ArtifactsForDelivery -token 'token' -artifacts 'current' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps,Dependencies' -branch 'main' | Should -BeExactly 'MyProject'

        Should -Invoke DownloadRelease -ModuleName Deliver -Times 2 -Exactly
        Should -Invoke GetArtifacts -ModuleName Deliver -Times 0 -Exactly
    }

    It 'falls back to the latest build artifacts when current is specified and no releases exist' {
        Mock GetReleases { return @() } -ModuleName Deliver

        Get-ArtifactsForDelivery -token 'token' -artifacts 'current' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps,Dependencies' -branch 'main' | Should -BeExactly 'MyProject'

        Should -Invoke DownloadRelease -ModuleName Deliver -Times 0 -Exactly
        Should -Invoke GetArtifacts -ModuleName Deliver -Times 2 -Exactly
        Should -Invoke GetArtifacts -ModuleName Deliver -Times 1 -Exactly -ParameterFilter { $version -eq 'latest' -and $mask -eq 'Apps' -and $branch -eq 'main' }
        Should -Invoke DownloadArtifact -ModuleName Deliver -Times 2 -Exactly
    }

    It 'throws when prerelease is specified and no releases exist' {
        Mock GetReleases { return @() } -ModuleName Deliver

        { Get-ArtifactsForDelivery -token 'token' -artifacts 'prerelease' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps' -branch 'main' } | Should -Throw '*was not found on any release*'

        Should -Invoke GetArtifacts -ModuleName Deliver -Times 0 -Exactly
    }

    It 'throws when releases exist, but none of them match the requested version' {
        Mock GetReleases {
            return @([PSCustomObject]@{ tag_name = '1.0.0-beta'; prerelease = $true; draft = $false })
        } -ModuleName Deliver

        { Get-ArtifactsForDelivery -token 'token' -artifacts 'current' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps' -branch 'main' } | Should -Throw '*Unable to locate current release*'

        Should -Invoke GetArtifacts -ModuleName Deliver -Times 0 -Exactly
    }

    It 'searches for build artifacts when a version number is specified' {
        Mock GetReleases { throw 'GetReleases should not be called' } -ModuleName Deliver

        Get-ArtifactsForDelivery -token 'token' -artifacts '1.0.0.0' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps' -branch 'main' | Should -BeExactly 'MyProject'

        Should -Invoke GetArtifacts -ModuleName Deliver -Times 1 -Exactly -ParameterFilter { $version -eq '1.0.0.0' }
    }

    It 'throws when no Apps artifacts are found' {
        Mock GetReleases { return @() } -ModuleName Deliver
        Mock GetArtifacts { return @() } -ModuleName Deliver

        { Get-ArtifactsForDelivery -token 'token' -artifacts 'current' -artifactsFolder $artifactsFolder -project 'MyProject' -atypes 'Apps' -branch 'main' } | Should -Throw '*Could not find any Apps artifacts*'
    }

    It 'uses the release asset naming convention for the project when downloading releases' {
        Mock GetReleases {
            return @([PSCustomObject]@{ tag_name = '1.0.0'; prerelease = $false; draft = $false })
        } -ModuleName Deliver

        Get-ArtifactsForDelivery -token 'token' -artifacts 'current' -artifactsFolder $artifactsFolder -project 'My Project' -atypes 'Apps' -branch 'main' | Should -BeExactly 'My.Project'
    }

    It 'uses the build artifact naming convention for the project when falling back to the latest build' {
        Mock GetReleases { return @() } -ModuleName Deliver

        Get-ArtifactsForDelivery -token 'token' -artifacts 'current' -artifactsFolder $artifactsFolder -project 'My Project' -atypes 'Apps' -branch 'main' | Should -BeExactly 'My Project'

        Should -Invoke GetArtifacts -ModuleName Deliver -Times 1 -Exactly -ParameterFilter { $projects -eq 'My Project' }
    }

    AfterEach {
        Remove-Item $artifactsFolder -Force -Recurse -ErrorAction SilentlyContinue
    }
}
