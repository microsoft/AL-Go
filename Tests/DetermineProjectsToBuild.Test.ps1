Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force

Describe "Get-ProjectsToBuild" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        Import-Module (Join-Path $PSScriptRoot "../Actions/DetermineProjectsToBuild/DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'baseFolder', Justification = 'False positive.')]
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'loads a single project in the root folder' {
        New-Item -Path "$baseFolder/.AL-Go/settings.json" -type File -Force

        # Add AL-Go settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @(".")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @(".")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['.'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "."
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
    #             "buildMode": "Default",
        #         "project": "."
        #       }
        #    ]
        #  }
        #]
        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @(".")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "."
    }

    It 'loads two independent projects with no build modes set' {
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        # Add AL-Go settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #    ]
        #  }
        #]
        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads two independent projects with build modes set' {
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -Value $(@{ buildModes = @("Default", "Clean") } | ConvertTo-Json ) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -Value $(@{ buildModes = @("Translated") } | ConvertTo-Json ) -type File -Force

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Clean",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Translated",
        #         "project": "Project2"
        #       },
        #    ]
        #  }
        #]
        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 3
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Clean"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[2].buildMode | Should -BeExactly "Translated"
        $buildOrder[0].buildDimensions[2].project | Should -BeExactly "Project2"
    }

    It 'loads correct projects, based on the modified files: single modified file in Project1' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        $modifiedFiles = @('Project1/.AL-Go/settings.json')
        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles -buildAllProjects $false

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @("Project1")
        $projectsToBuild | Should -BeExactly @("Project1")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       }
        #    ]
        #  }
        #]
        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
    }

    It 'loads correct projects, based on the modified files: multiple modified files in Project1 and Project2' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        $modifiedFiles = @('Project1/.AL-Go/settings.json', 'Project2/.AL-Go/settings.json')
        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles -buildAllProjects $false

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @("Project1", "Project2")
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #       }
        #    ]
        #  }
        #]
        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads correct projects, based on the modified files: multiple modified files only in Project1' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        $modifiedFiles = @('Project1/.AL-Go/settings.json', 'Project1/app/app.json')
        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles -buildAllProjects $false

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @("Project1")
        $projectsToBuild | Should -BeExactly @("Project1")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
    }

    It 'loads correct projects, based on the modified files: no modified files' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        $modifiedFiles = @()
        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles -buildAllProjects $true

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #       }
        #    ]
        #  }
        #]
        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads correct projects, based on the modified files: Project1 is modified, fullBuildPatterns is set to .github' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        # Add AL-Go settings file
        $alGoSettings = @{ projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false; fullBuildPatterns = @('.github') }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $modifiedFiles = @('Project1/.AL-Go/settings.json')
        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles -buildAllProjects $false

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @("Project1")
        $projectsToBuild | Should -BeExactly @("Project1")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
    }

    It 'loads correct projects, based on the modified files: Project1 is modified, fullBuildPatterns is set to Project1/*' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        # Add AL-Go settings file
        $alGoSettings = @{ projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false; fullBuildPatterns = @('Project1/*') }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $modifiedFiles = @('Project1/.AL-Go/settings.json')
        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @("Project1")
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads independent projects correctly, if useProjectDependencies is set to false' {
        # Two independent projects, no dependencies
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        #Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads independent projects correctly, if useProjectDependencies is set to true' {
        # Two independent projects, no dependencies
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        #Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $true }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads dependent projects correctly, if useProjectDependencies is set to false' {
        # Two dependent projects
        $dependencyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependencyAppFile -Depth 10) -type File -Force

        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        # Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"

        # Test that setting postponeProjectInBuildOrder to true doesn't have any effect when useProjectDependencies is false
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; postponeProjectInBuildOrder = $true; useProjectDependencies = $false }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1",
        #      "Project2"
        #    ],
        #    "projectsCount":  2,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       },
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 1
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2"
    }

    It 'loads dependent projects correctly, if useProjectDependencies is set to true' {
        # Two dependent projects
        $dependencyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependencyAppFile -Depth 10) -type File -Force

        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        # Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        # Add settings as environment variable to simulate we've run ReadSettings
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @("Project1")

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1"
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       }
        #    ]
        #  },
        #  {
        #    "projects":  [
        #      "Project2"
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 2
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"

        $buildOrder[1] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[1].projects | Should -BeExactly @("Project2")
        $buildOrder[1].projectsCount | Should -BeExactly 1
        $buildOrder[1].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[1].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[1].buildDimensions[0].project | Should -BeExactly "Project2"

        # Test that setting postponeProjectInBuildOrder to true in the last project in the build order doesn't fail or change anything
        $projectSettings = @{ "postponeProjectInBuildOrder" = $true }
        Set-Content -Path "$baseFolder/Project2/.AL-Go/settings.json" -Value (ConvertTo-Json $projectSettings -Depth 10)

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @("Project1")

        # Build order should have the following structure:
        #[
        #  {
        #    "projects":  [
        #      "Project1"
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project1"
        #       }
        #    ]
        #  },
        #  {
        #    "projects":  [
        #      "Project2"
        #    ],
        #    "projectsCount":  1,
        #    "buildDimensions":  [
        #       {
        #         "buildMode": "Default",
        #         "project": "Project2"
        #       }
        #    ]
        #  }
        #]

        $buildOrder.Count | Should -BeExactly 2
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"

        $buildOrder[1] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[1].projects | Should -BeExactly @("Project2")
        $buildOrder[1].projectsCount | Should -BeExactly 1
        $buildOrder[1].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[1].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[1].buildDimensions[0].project | Should -BeExactly "Project2"
    }

    It 'loads dependent projects correctly, if useProjectDependencies is set to false in a project setting' {
        # Add three dependent projects
        # Project 1
        # Project 2 depends on Project 1 - useProjectDependencies is set to true from the repo settings
        # Project 3 depends on Project 1, but has useProjectDependencies set to false in the project settings
        $dependencyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependencyAppFile -Depth 10) -type File -Force

        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        # Third project that also depends on the first project, but has useProjectDependencies set to false
        $dependantAppFile3 = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd3'; name = 'Third App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project3/.AL-Go/settings.json" -type File -Force
        @{ useProjectDependencies = $false } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "Project3/.AL-Go/settings.json") -Encoding UTF8
        New-Item -Path "$baseFolder/Project3/app/app.json" -Value (ConvertTo-Json $dependantAppFile3 -Depth 10) -type File -Force

        #Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        # Add settings as environment variable to simulate we've run ReadSettings
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2", "Project3")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @('Project1', 'Project2', 'Project3')

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @("Project1")
        $projectDependencies['Project3'] | Should -BeExactly @()

        # Build order should have the following structure:
        #[
        #{
        #    "buildDimensions": [
        #    {
        #        "projectName": "Project1",
        #        "buildMode": "Default",
        #        "project": "Project1",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    },
        #    {
        #        "projectName": "Project3",
        #        "buildMode": "Default",
        #        "project": "Project3",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    }
        #    ],
        #    "projectsCount": 2,
        #    "projects": [
        #    "Project1",
        #    "Project3"
        #    ]
        #},
        #{
        #    "buildDimensions": [
        #    {
        #        "projectName": "Project2",
        #        "buildMode": "Default",
        #        "project": "Project2",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    }
        #    ],
        #    "projectsCount": 1,
        #    "projects": [
        #    "Project2"
        #    ]
        #}
        #]
        $buildOrder.Count | Should -BeExactly 2
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project3")
        $buildOrder[0].projectsCount | Should -BeExactly 2
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project3"

        $buildOrder[1] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[1].projects | Should -BeExactly @("Project2")
        $buildOrder[1].projectsCount | Should -BeExactly 1
        $buildOrder[1].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[1].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[1].buildDimensions[0].project | Should -BeExactly "Project2"
    }

    It 'throws if the calculated build depth is more than the maximum supported' {
        # Two dependent projects
        $dependencyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependencyAppFile -Depth 10) -type File -Force

        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        #Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        # Add settings as environment variable to simulate we've run ReadSettings
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        { Get-ProjectsToBuild -baseFolder $baseFolder -maxBuildDepth 1 } | Should -Throw "The build depth is too deep, the maximum build depth is 1. You need to run 'Update AL-Go System Files' to update the workflows"
    }

    It 'postpones projects if postponeProjectInBuildOrder is set to true' {
        # Add three dependent projects
        # Project 1
        # Project 2 depends on Project 1, has postponeProjectInBuildOrder set to true
        # Project 3 depends on Project 1, has postponeProjectInBuildOrder set to true
        # Project 4 depends on Project 2
        $dependencyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependencyAppFile -Depth 10) -type File -Force

        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        @{ postponeProjectInBuildOrder = $true } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "Project2/.AL-Go/settings.json") -Encoding UTF8
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        $dependantAppFile3 = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd3'; name = 'Third App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project3/.AL-Go/settings.json" -type File -Force
        @{ postponeProjectInBuildOrder = $true } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "Project3/.AL-Go/settings.json") -Encoding UTF8
        New-Item -Path "$baseFolder/Project3/app/app.json" -Value (ConvertTo-Json $dependantAppFile3 -Depth 10) -type File -Force

        $dependantAppFile4 = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd4'; name = 'Fourth App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project4/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project4/app/app.json" -Value (ConvertTo-Json $dependantAppFile4 -Depth 10) -type File -Force

        #Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        # Add settings as environment variable to simulate we've run ReadSettings
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2", "Project3", "Project4")
        $modifiedProjects | Should -BeExactly @()
        $projectsToBuild | Should -BeExactly @('Project1', 'Project2', 'Project3', 'Project4')

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @("Project1")
        $projectDependencies['Project3'] | Should -BeExactly @("Project1")
        $projectDependencies['Project4'] | Should -BeExactly @("Project2", "Project1")

        # Build order should have the following structure:
        #[
        #{
        #    "buildDimensions": [
        #    {
        #        "projectName": "Project1",
        #        "buildMode": "Default",
        #        "project": "Project1",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    },
        #    ],
        #    "projectsCount": 1,
        #    "projects": [
        #    "Project1"
        #    ]
        #},
        #{
        #    "buildDimensions": [
        #    {
        #        "projectName": "Project2",
        #        "buildMode": "Default",
        #        "project": "Project2",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    }
        #    ],
        #    "projectsCount": 1,
        #    "projects": [
        #    "Project2"
        #    ]
        #}
        #{
        #    "buildDimensions": [
        #    {
        #        "projectName": "Project3",
        #        "buildMode": "Default",
        #        "project": "Project3",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    },
        #    {
        #        "projectName": "Project4",
        #        "buildMode": "Default",
        #        "project": "Project4",
        #        "githubRunnerShell": "powershell",
        #        "gitHubRunner": "\"windows-latest\""
        #    }
        #    ],
        #    "projectsCount": 2,
        #    "projects": [
        #    "Project3",
        #    "Project4"
        #    ]
        #}
        #]
        $buildOrder.Count | Should -BeExactly 3
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[0].projectsCount | Should -BeExactly 1
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1"

        $buildOrder[1] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[1].projects | Should -BeExactly @("Project2")
        $buildOrder[1].projectsCount | Should -BeExactly 1
        $buildOrder[1].buildDimensions.Count | Should -BeExactly 1
        $buildOrder[1].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[1].buildDimensions[0].project | Should -BeExactly "Project2"

        $buildOrder[2] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[2].projects | Should -BeExactly @("Project4", "Project3")
        $buildOrder[2].projectsCount | Should -BeExactly 2
        $buildOrder[2].buildDimensions.Count | Should -BeExactly 2
        $buildOrder[2].buildDimensions[0].buildMode | Should -BeExactly "Default"
        $buildOrder[2].buildDimensions[0].project | Should -BeExactly "Project4"
        $buildOrder[2].buildDimensions[1].buildMode | Should -BeExactly "Default"
        $buildOrder[2].buildDimensions[1].project | Should -BeExactly "Project3"
    }

    It 'resolves test project dependencies from projectsToTest setting' {
        # Project1 has an app
        $project1AppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $project1AppFile -Depth 10) -type File -Force

        # TestProject is a test-only project that depends on Project1 via projectsToTest setting
        New-Item -Path "$baseFolder/TestProject/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("Project1") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject/.AL-Go/settings.json") -Encoding UTF8

        # Add settings file
        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "TestProject")
        $projectsToBuild | Should -BeExactly @("Project1", "TestProject")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable
        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['TestProject'] | Should -BeExactly @("Project1")

        # Build order: Project1 first, then TestProject
        $buildOrder.Count | Should -BeExactly 2
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[1].projects | Should -BeExactly @("TestProject")
    }

    It 'resolves test project with transitive dependencies' {
        # Project1 (base) -> Project2 depends on Project1 -> TestProject depends on Project2
        $project1AppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $project1AppFile -Depth 10) -type File -Force

        $project2AppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $project2AppFile -Depth 10) -type File -Force

        # TestProject depends on Project2 (which transitively depends on Project1)
        New-Item -Path "$baseFolder/TestProject/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("Project2") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject/.AL-Go/settings.json") -Encoding UTF8

        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2", "TestProject")

        $projectDependencies['Project1'] | Should -BeExactly @()
        $projectDependencies['Project2'] | Should -BeExactly @("Project1")
        # TestProject should depend on both Project2 AND Project1 (transitive)
        $projectDependencies['TestProject'] | Should -Contain "Project1"
        $projectDependencies['TestProject'] | Should -Contain "Project2"

        # Build order: Project1 first, Project2 second, TestProject last
        $buildOrder.Count | Should -BeExactly 3
        $buildOrder[0].projects | Should -BeExactly @("Project1")
        $buildOrder[1].projects | Should -BeExactly @("Project2")
        $buildOrder[2].projects | Should -BeExactly @("TestProject")
    }

    It 'throws error when test project has buildable app folders' {
        # TestProject has both projectsToTest setting AND an app folder - this should fail

        $appFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appFile -Depth 10) -type File -Force

        New-Item -Path "$baseFolder/TestProject/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("Project1") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject/.AL-Go/settings.json") -Encoding UTF8
        # Add an app folder to the test project - this should be forbidden
        $testAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Bad App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/TestProject/app/app.json" -Value (ConvertTo-Json $testAppFile -Depth 10) -type File -Force

        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        { Get-ProjectsToBuild -baseFolder $baseFolder } | Should -Throw "*must not contain buildable code*"
    }

    It 'throws error when test project has buildable test folders' {
        # TestProject has both projectsToTest setting AND a test folder - this should fail

        $appFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appFile -Depth 10) -type File -Force

        # Add a test folder with an app to the test project
        $testAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd3'; name = 'Bad Test App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/TestProject/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/TestProject/test/app.json" -Value (ConvertTo-Json $testAppFile -Depth 10) -type File -Force
        @{ projectsToTest = @("Project1"); testFolders = @("test") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject/.AL-Go/settings.json") -Encoding UTF8

        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        { Get-ProjectsToBuild -baseFolder $baseFolder } | Should -Throw "*must not contain buildable code*"
    }

    It 'throws error when one test project depends on another test project' {
        # Project1 is a normal project, TestProject1 and TestProject2 are both test projects
        # TestProject2 tries to depend on TestProject1 - this should fail
        Mock OutputError {} -ModuleName DetermineProjectsToBuild

        $appFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appFile -Depth 10) -type File -Force

        New-Item -Path "$baseFolder/TestProject1/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("Project1") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject1/.AL-Go/settings.json") -Encoding UTF8

        New-Item -Path "$baseFolder/TestProject2/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("TestProject1") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject2/.AL-Go/settings.json") -Encoding UTF8

        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        { Get-ProjectsToBuild -baseFolder $baseFolder } | Should -Throw
        Should -Invoke OutputError -ModuleName DetermineProjectsToBuild -ParameterFilter { $message -like "*cannot depend on another test project*" }
    }

    It 'throws error when projectsToTest references nonexistent project' {
        # Project1 exists
        Mock OutputError {} -ModuleName DetermineProjectsToBuild

        $project1AppFile= @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $project1AppFile -Depth 10) -type File -Force

        # TestProject references NonExistentProject
        New-Item -Path "$baseFolder/TestProject/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("NonExistentProject") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject/.AL-Go/settings.json") -Encoding UTF8

        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        { Get-ProjectsToBuild -baseFolder $baseFolder } | Should -Throw
        Should -Invoke OutputError -ModuleName DetermineProjectsToBuild -ParameterFilter { $message -like "*does not exist*" }
    }

    It 'test project can depend on multiple upstream projects' {
        # Project1 and Project2 are independent
        $project1AppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $project1AppFile -Depth 10) -type File -Force

        $project2AppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $project2AppFile -Depth 10) -type File -Force

        # TestProject depends on both Project1 and Project2
        New-Item -Path "$baseFolder/TestProject/.AL-Go/settings.json" -type File -Force
        @{ projectsToTest = @("Project1", "Project2") } | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder "TestProject/.AL-Go/settings.json") -Encoding UTF8

        $alGoSettings = @{ fullBuildPatterns = @(); projects = @(); powerPlatformSolutionFolder = ''; useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github" -type Directory -Force
        $alGoSettings | ConvertTo-Json -Depth 99 -Compress | Out-File (Join-Path $baseFolder ".github/AL-Go-Settings.json") -Encoding UTF8

        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $allProjects, $modifiedProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $projectDependencies['TestProject'] | Should -Contain "Project1"
        $projectDependencies['TestProject'] | Should -Contain "Project2"

        # Build order: Project1 and Project2 in first layer (parallel), TestProject in second layer
        $buildOrder.Count | Should -BeExactly 2
        $buildOrder[0].projects | Should -Contain "Project1"
        $buildOrder[0].projects | Should -Contain "Project2"
        $buildOrder[1].projects | Should -BeExactly @("TestProject")
    }

    AfterEach {
        Remove-Item $baseFolder -Force -Recurse
    }
}

Describe "Get-BuildAllProjects" {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot "../Actions/DetermineProjectsToBuild/DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'baseFolder', Justification = 'False positive.')]
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It ('returns false if there are no modified files') {
        # Add AL-Go settings
        $alGoSettings = @{ fullBuildPatterns = @() }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $buildAllProjects = Get-BuildAllProjects -baseFolder $baseFolder
        $buildAllProjects | Should -Be $false
    }

    It ('returns true if any of the modified files matches any of the patterns in fullBuildPatterns setting') {
        # Add AL-Go settings
        $alGoSettings = @{ fullBuildPatterns = @('Project1/*') }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $modifiedFiles = @('Project1/.AL-Go/settings.json', 'Project2/.AL-Go/settings.json')
        $buildAllProjects = Get-BuildAllProjects -baseFolder $baseFolder -modifiedFiles $modifiedFiles
        $buildAllProjects | Should -Be $true
    }

    It ('returns false if the modified files are less than 250 and none of them matches any of the patterns in fullBuildPatterns setting') {
        # Add AL-Go settings
        $alGoSettings = @{ fullBuildPatterns = @('Project1/*') }
        $env:Settings = ConvertTo-Json $alGoSettings -Depth 99 -Compress

        $modifiedFiles = @('Project2/.AL-Go/settings.json', 'Project3/.AL-Go/settings.json')
        $buildAllProjects = Get-BuildAllProjects -baseFolder $baseFolder -modifiedFiles $modifiedFiles
        $buildAllProjects | Should -Be $false
    }

    AfterEach {
        Remove-Item $baseFolder -Force -Recurse
    }
}
