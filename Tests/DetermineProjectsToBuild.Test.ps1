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

        $project1AppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
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

Describe "Get-UnmodifiedAppsFromBaselineWorkflowRun" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        Import-Module (Join-Path $PSScriptRoot "../Actions/DetermineProjectsToBuild/DetermineProjectsToBuild.psm1" -Resolve) -DisableNameChecking -Force
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'baseFolder', Justification = 'False positive.')]
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'correctly identifies unmodified apps when appFolders reference paths above the project folder via ../' {
        # Repo layout where the project is nested and appFolders reference sources via ../:
        #   baseFolder/
        #     .github/AL-Go-Settings.json
        #     src/Apps/AppA/App/app.json        (modified)
        #     src/Apps/AppB/App/app.json        (unmodified - should be downloaded from baseline)
        #     src/Apps/AppC/App/app.json        (unmodified - should be downloaded from baseline)
        #     build/projects/MyProject/.AL-Go/settings.json
        #       appFolders: ["../../../src/Apps/*/App"]

        $project = 'build/projects/MyProject'
        $projectPath = Join-Path $baseFolder $project

        # Create repo-level AL-Go settings
        $repoSettings = @{
            fullBuildPatterns = @()
            projects = @($project)
            powerPlatformSolutionFolder = ''
            useProjectDependencies = $false
            incrementalBuilds = @{
                onPull_Request = $true
                mode = 'modifiedApps'
            }
        }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $repoSettings -Depth 10) -type File -Force | Out-Null

        # Create project-level settings with appFolders that go above the project
        $projectSettingsJson = @{
            appFolders = @("../../../src/Apps/*/App")
            testFolders = @()
            bcptTestFolders = @()
        }
        New-Item -Path "$projectPath/.AL-Go/settings.json" -Value (ConvertTo-Json $projectSettingsJson -Depth 10) -type File -Force | Out-Null

        # Create three independent apps
        $appA = @{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; name = 'App A'; publisher = 'TestPublisher'; version = '1.0.0.0'; dependencies = @() }
        $appB = @{ id = 'bbbbbbbb-0000-0000-0000-000000000002'; name = 'App B'; publisher = 'TestPublisher'; version = '1.0.0.0'; dependencies = @() }
        $appC = @{ id = 'cccccccc-0000-0000-0000-000000000003'; name = 'App C'; publisher = 'TestPublisher'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/src/Apps/AppA/App/app.json" -Value (ConvertTo-Json $appA -Depth 10) -type File -Force | Out-Null
        New-Item -Path "$baseFolder/src/Apps/AppB/App/app.json" -Value (ConvertTo-Json $appB -Depth 10) -type File -Force | Out-Null
        New-Item -Path "$baseFolder/src/Apps/AppC/App/app.json" -Value (ConvertTo-Json $appC -Depth 10) -type File -Force | Out-Null

        # Also create a dummy .al file so there's something to be "modified"
        New-Item -Path "$baseFolder/src/Apps/AppA/App/MyCodeunit.al" -Value "// modified file" -type File -Force | Out-Null

        # Set env:Settings for helper functions
        $env:Settings = ConvertTo-Json $repoSettings -Depth 99 -Compress

        # Resolve appFolders the way ResolveProjectFolders/AnalyzeRepo does:
        # Push-Location to project, Resolve-Path -Relative
        Push-Location $projectPath
        $resolvedAppFolders = @(Resolve-Path "../../../src/Apps/*/App" -Relative -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_ 'app.json') })
        Pop-Location

        # Build a settings hashtable with resolved folders (same as what RunPipeline passes in)
        $resolvedSettings = @{
            appFolders = $resolvedAppFolders
            testFolders = @()
            bcptTestFolders = @()
        }

        # Build artifact folder
        $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
        New-Item -Path $buildArtifactFolder -ItemType Directory -Force | Out-Null

        # Only AppA is modified
        $sep = [System.IO.Path]::DirectorySeparatorChar
        $modifiedFiles = @("src${sep}Apps${sep}AppA${sep}App${sep}MyCodeunit.al")

        # Mock GitHub API calls since we don't have a real baseline workflow
        # Stub functions that are normally provided by GitHub Actions runtime
        if (-not (Get-Command 'Trace-Information' -ErrorAction SilentlyContinue)) {
            function global:Trace-Information { param([string]$Message, $AdditionalData) }
        }
        $env:GITHUB_API_URL = 'https://api.github.com'
        $env:GITHUB_REPOSITORY = 'test/repo'
        Mock InvokeWebRequest {
            # Return a mock response object that mimics the GitHub API
            $uri = $args[0]
            if (-not $uri) { $uri = $Uri }
            $content = if ($uri -like '*/actions/runs/*/artifacts*') {
                # Artifacts endpoint - return empty list to stop pagination
                '{"artifacts":[]}'
            } else {
                # Workflow run info endpoint
                '{"head_branch":"main"}'
            }
            return [PSCustomObject]@{ Content = $content }
        } -ModuleName 'Github-Helper'

        # Capture Write-Host output to verify download folder matching
        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host { $null = $script:capturedOutput.Add($Object) } -ModuleName 'DetermineProjectsToBuild'

        Get-UnmodifiedAppsFromBaselineWorkflowRun `
            -token 'fake-token' `
            -settings $resolvedSettings `
            -baseFolder $baseFolder `
            -project $project `
            -baselineWorkflowRunId '12345' `
            -modifiedFiles $modifiedFiles `
            -buildArtifactFolder $buildArtifactFolder `
            -buildMode 'Default' `
            -projectPath $projectPath

        # The output should list the unmodified app folders (AppB and AppC) as download candidates.
        # Before the fix: the download list was always empty ("- None") because the path matching
        # used SubString(2) which mangled paths starting with ..\ into nonsense like \..\..\src\...
        $downloadAppLine = $script:capturedOutput | Where-Object { $_ -eq 'Download appFolders:' }
        $downloadAppLine | Should -Not -BeNullOrEmpty -Because "the function should output the 'Download appFolders:' header"

        # Find entries after "Download appFolders:" up to the next section header
        $inDownloadSection = $false
        $downloadEntries = @()
        foreach ($line in $script:capturedOutput) {
            if ($line -eq 'Download appFolders:') {
                $inDownloadSection = $true
                continue
            }
            if ($inDownloadSection) {
                if ($line -match '^Download (test|bcpt)') { break }
                $downloadEntries += $line
            }
        }

        # With the bug: downloadEntries would be @("- None") because the path matching fails
        # With the fix: downloadEntries should contain AppB and AppC folders
        $downloadEntries | Should -Not -Contain '- None' -Because "unmodified apps should be identified for download from baseline"
        ($downloadEntries | Where-Object { $_ -like '*AppB*' }) | Should -Not -BeNullOrEmpty -Because "AppB was not modified and should be downloaded from baseline"
        ($downloadEntries | Where-Object { $_ -like '*AppC*' }) | Should -Not -BeNullOrEmpty -Because "AppC was not modified and should be downloaded from baseline"
        ($downloadEntries | Where-Object { $_ -like '*AppA*' }) | Should -BeNullOrEmpty -Because "AppA was modified and should NOT be downloaded from baseline"
    }

    It 'also works when appFolders are inside the project folder (standard layout)' {
        # Standard layout where apps are inside the project folder:
        #   baseFolder/
        #     .AL-Go/settings.json
        #     .github/AL-Go-Settings.json
        #     app1/app.json
        #     app2/app.json

        $project = ''
        $projectPath = $baseFolder

        # Create repo-level AL-Go settings
        $repoSettings = @{
            fullBuildPatterns = @()
            projects = @()
            powerPlatformSolutionFolder = ''
            useProjectDependencies = $false
            incrementalBuilds = @{
                onPull_Request = $true
                mode = 'modifiedApps'
            }
        }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $repoSettings -Depth 10) -type File -Force | Out-Null
        New-Item -Path "$baseFolder/.AL-Go/settings.json" -Value (ConvertTo-Json @{} -Depth 10) -type File -Force | Out-Null

        # Create two apps inside the project folder
        $app1 = @{ id = '11111111-0000-0000-0000-000000000001'; name = 'App One'; publisher = 'TestPublisher'; version = '1.0.0.0'; dependencies = @() }
        $app2 = @{ id = '22222222-0000-0000-0000-000000000002'; name = 'App Two'; publisher = 'TestPublisher'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/app1/app.json" -Value (ConvertTo-Json $app1 -Depth 10) -type File -Force | Out-Null
        New-Item -Path "$baseFolder/app2/app.json" -Value (ConvertTo-Json $app2 -Depth 10) -type File -Force | Out-Null
        New-Item -Path "$baseFolder/app1/MyCodeunit.al" -Value "// modified file" -type File -Force | Out-Null

        $env:Settings = ConvertTo-Json $repoSettings -Depth 99 -Compress

        # Resolve appFolders (standard layout: .\ prefix)
        $resolvedSettings = @{
            appFolders = @('.\app1', '.\app2')
            testFolders = @()
            bcptTestFolders = @()
        }

        $buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
        New-Item -Path $buildArtifactFolder -ItemType Directory -Force | Out-Null

        # Only app1 is modified
        $sep = [System.IO.Path]::DirectorySeparatorChar
        $modifiedFiles = @("app1${sep}MyCodeunit.al")

        Mock InvokeWebRequest {
            $uri = $args[0]
            if (-not $uri) { $uri = $Uri }
            $content = if ($uri -like '*/actions/runs/*/artifacts*') {
                '{"artifacts":[]}'
            } else {
                '{"head_branch":"main"}'
            }
            return [PSCustomObject]@{ Content = $content }
        } -ModuleName 'Github-Helper'
        # Stub Trace-Information if not already defined (normally loaded by Invoke-AlGoAction.ps1)
        if (-not (Get-Command 'Trace-Information' -ErrorAction SilentlyContinue)) {
            function global:Trace-Information { param([string]$Message, $AdditionalData) }
        }
        $env:GITHUB_API_URL = 'https://api.github.com'
        $env:GITHUB_REPOSITORY = 'test/repo'

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host { $null = $script:capturedOutput.Add($Object) } -ModuleName 'DetermineProjectsToBuild'

        Get-UnmodifiedAppsFromBaselineWorkflowRun `
            -token 'fake-token' `
            -settings $resolvedSettings `
            -baseFolder $baseFolder `
            -project $project `
            -baselineWorkflowRunId '12345' `
            -modifiedFiles $modifiedFiles `
            -buildArtifactFolder $buildArtifactFolder `
            -buildMode 'Default' `
            -projectPath $projectPath

        $inDownloadSection = $false
        $downloadEntries = @()
        foreach ($line in $script:capturedOutput) {
            if ($line -eq 'Download appFolders:') {
                $inDownloadSection = $true
                continue
            }
            if ($inDownloadSection) {
                if ($line -match '^Download (test|bcpt)') { break }
                $downloadEntries += $line
            }
        }

        # app2 should be marked for download (unmodified), app1 should not
        $downloadEntries | Should -Not -Contain '- None' -Because "the unmodified app2 should be identified for download"
        ($downloadEntries | Where-Object { $_ -like '*app2*' }) | Should -Not -BeNullOrEmpty -Because "app2 was not modified and should be downloaded from baseline"
        ($downloadEntries | Where-Object { $_ -like '*app1*' }) | Should -BeNullOrEmpty -Because "app1 was modified and should NOT be downloaded from baseline"
    }

    AfterEach {
        Remove-Item $baseFolder -Force -Recurse
    }
}
