Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force
$bcContainerHelperPath = $null

Describe "Get-ProjectsToBuild" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        $bcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        $scriptPath = Join-Path $PSScriptRoot "../Actions/DetermineProjectsToBuild/DetermineProjectsToBuild.ps1" -Resolve
        . $scriptPath
    }

    BeforeEach {
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'loads a single project in the root folder' {
        New-Item -Path "$baseFolder/.AL-Go/settings.json" -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @(".")
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

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
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

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
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

    It 'loads correct projects, based on the modified files' {
        # Setup project structure
        $appJson = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'My app'; publisher = 'Contoso'; version = '1.0.0.0' }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $appJson) -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        
        # Add AL-Go settings file
        $alGoSettings = @{ alwaysBuildAllProjects = $false }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings -Depth 99) -type File -Force

        #region Single file modified
        $modifiedFiles = @('Project1/.AL-Go/settings.json')
        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles

        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        #endregion

        #region Multiple files modified
        $modifiedFiles = @('Project1/.AL-Go/settings.json', 'Project2/.AL-Go/settings.json')
        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles

        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        #endregion

        #region Multiple files modified, but only one project
        $modifiedFiles = @('Project1/.AL-Go/settings.json', 'Project1/app/app.json')
        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles

        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        #endregion


        #region No modified files
        $modifiedFiles = @()
        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles

        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        #endregion

        #region One project is modified, but alwaysBuildAllProjects is set to true
        #Add settings file
        $alGoSettings = @{ alwaysBuildAllProjects = $true }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings) -type File -Force

        $modifiedFiles = @('Project1/.AL-Go/settings.json')
        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder -modifiedFiles $modifiedFiles

        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        #endregion
    }

    It 'loads independent projects correctly, if useProjectDependencies is set to false' {
        # Two independent projects, no dependencies
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force

        #Add settings file
        $alGoSettings = @{ useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings) -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder
        
        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        $alGoSettings = @{ useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings) -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder
        
        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        $dependecyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependecyAppFile -Depth 10) -type File -Force
        
        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        #Add settings file
        $alGoSettings = @{ useProjectDependencies = $false }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings) -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
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
        $dependecyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependecyAppFile -Depth 10) -type File -Force
        
        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        #Add settings file
        $alGoSettings = @{ useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings) -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
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

    It 'throws if the calculated build depth is more than the maximum supported' {
        # Two dependent projects
        $dependecyAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @() }
        New-Item -Path "$baseFolder/Project1/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project1/app/app.json" -Value (ConvertTo-Json $dependecyAppFile -Depth 10) -type File -Force
        
        $dependantAppFile = @{ id = '83fb8305-4079-415d-a25d-8132f0436fd2'; name = 'Second App'; publisher = 'Contoso'; version = '1.0.0.0'; dependencies = @(@{id = '83fb8305-4079-415d-a25d-8132f0436fd1'; name = 'First App'; publisher = 'Contoso'; version = '1.0.0.0'} ) }
        New-Item -Path "$baseFolder/Project2/.AL-Go/settings.json" -type File -Force
        New-Item -Path "$baseFolder/Project2/app/app.json" -Value (ConvertTo-Json $dependantAppFile -Depth 10) -type File -Force

        #Add settings file
        $alGoSettings = @{ useProjectDependencies = $true }
        New-Item -Path "$baseFolder/.github/AL-Go-Settings.json" -Value (ConvertTo-Json $alGoSettings) -type File -Force

        { Get-ProjectsToBuild -baseFolder $baseFolder -maxBuildDepth 1 } | Should -Throw "The build depth is too deep, the maximum build depth is 1. You need to run 'Update AL-Go System Files' to update the workflows"
    }

    AfterEach {
        Remove-Item $baseFolder -Force -Recurse
    }

    AfterAll {
        CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    }
}
