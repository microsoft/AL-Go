Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force
$bcContainerHelperPath = $null

Describe "Get-ProjectsToBuild" {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "..\Actions\AL-Go-Helper.ps1" -Resolve)
        $bcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $([System.IO.Path]::GetTempPath())

        $scriptPath = Join-Path $PSScriptRoot "..\Actions\DetermineProjectsToBuild\DetermineProjectsToBuild.ps1" -Resolve
        . $scriptPath
    }

    BeforeEach {
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'loads a single project in the root folder' {
        New-Item -Path "$baseFolder\.AL-Go\settings.json" -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @(".") -Because "allProjects should contain only the root project"
        $projectsToBuild | Should -BeExactly @(".") -Because "projectsToBuild should contain only the root project"

        $projectDependencies | Should -BeOfType System.Collections.Hashtable -Because "projectDependencies should should be a hashtable"
        $projectDependencies['.'] | Should -BeExactly @() -Because "projectDependencies should contain no dependencies for the root project"
       
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
        $buildOrder.Count | Should -BeExactly 1 -Because "buildOrder should contain only have one level/depth"
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable -Because "buildOrder should contain only the root project"
        $buildOrder[0].projects | Should -BeExactly @(".") -Because "the projects in buildOrder should contain only the root project"
        $buildOrder[0].projectsCount | Should -BeExactly 1 -Because "the projects in buildOrder should contain only the root project"
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 1 -Because "the buildDimensions in buildOrder should contain only the root project"
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default" -Because "the buildMode in buildOrder should be 'Default'"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "." -Because "the project in buildOrder should be the root project"
    }

    
    It 'loads two independent projects with no build modes set' {
        New-Item -Path "$baseFolder\Project1\.AL-Go\settings.json" -type File -Force
        New-Item -Path "$baseFolder\Project2\.AL-Go\settings.json" -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable -Because "projectDependencies should should be a hashtable"
        $projectDependencies['Project1'] | Should -BeExactly @() -Because "projectDependencies should contain no dependencies for Project1"
        $projectDependencies['Project2'] | Should -BeExactly @() -Because "projectDependencies should contain no dependencies for Project2"
       
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
        $buildOrder.Count | Should -BeExactly 1 -Because "buildOrder should contain only have one level/depth"
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2 -Because "the projects in buildOrder should contain both projects"
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 2 -Because "the buildDimensions in buildOrder should contain both projects"
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default" -Because "the buildMode in buildOrder should be 'Default'"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1" -Because "the project in first buildOrder should be Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Default" -Because "the buildMode in buildOrder should be 'Default'"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project2" -Because "the project in second buildOrder should be Project2"
    }

    It 'loads two independent projects with build modes set' {
        New-Item -Path "$baseFolder\Project1\.AL-Go\settings.json" -Value $(@{ buildModes = @("Default", "Clean") } | ConvertTo-Json ) -type File -Force
        New-Item -Path "$baseFolder\Project2\.AL-Go\settings.json" -Value $(@{ buildModes = @("Translated") } | ConvertTo-Json ) -type File -Force

        $allProjects, $projectsToBuild, $projectDependencies, $buildOrder = Get-ProjectsToBuild -baseFolder $baseFolder

        $allProjects | Should -BeExactly @("Project1", "Project2")
        $projectsToBuild | Should -BeExactly @("Project1", "Project2")

        $projectDependencies | Should -BeOfType System.Collections.Hashtable -Because "projectDependencies should should be a hashtable"
        $projectDependencies['Project1'] | Should -BeExactly @() -Because "projectDependencies should contain no dependencies for Project1"
        $projectDependencies['Project2'] | Should -BeExactly @() -Because "projectDependencies should contain no dependencies for Project2"
       
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
        $buildOrder.Count | Should -BeExactly 1 -Because "buildOrder should contain only have one level/depth"
        $buildOrder[0] | Should -BeOfType System.Collections.Hashtable
        $buildOrder[0].projects | Should -BeExactly @("Project1", "Project2")
        $buildOrder[0].projectsCount | Should -BeExactly 2 -Because "the projects in buildOrder should contain both projects"
        $buildOrder[0].buildDimensions.Count | Should -BeExactly 3 -Because "the buildDimensions in buildOrder should contain three entries"
        $buildOrder[0].buildDimensions[0].buildMode | Should -BeExactly "Default" -Because "the buildMode in buildOrder should be 'Default'"
        $buildOrder[0].buildDimensions[0].project | Should -BeExactly "Project1" -Because "the project in first buildOrder should be Project1"
        $buildOrder[0].buildDimensions[1].buildMode | Should -BeExactly "Clean" -Because "the buildMode in buildOrder should be 'Clean'"
        $buildOrder[0].buildDimensions[1].project | Should -BeExactly "Project1" -Because "the project in second buildOrder should be Project1"
        $buildOrder[0].buildDimensions[2].buildMode | Should -BeExactly "Translated" -Because "the buildMode in buildOrder should be 'Translated'"
        $buildOrder[0].buildDimensions[2].project | Should -BeExactly "Project2" -Because "the project in third buildOrder should be Project2"
    }

    AfterEach {
        Remove-Item $env:GITHUB_OUTPUT -Force
        Remove-Item $baseFolder -Force -Recurse
    }

    AfterAll {
        CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    }
}
