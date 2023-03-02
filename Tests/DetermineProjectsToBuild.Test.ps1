Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force

Describe "DetermineProjectsToBuild Action Tests" {
    BeforeAll {
        $actionName = "DetermineProjectsToBuild"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    BeforeEach {
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $baseFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'loads a single project in the root folder' {
        New-Item -Path "$baseFolder\.AL-Go\settings.json" -type File -Force

        & $scriptPath `
            -baseFolder $baseFolder

        $generatedOutput = Get-Content $env:GITHUB_OUTPUT

        Write-Host $generatedOutput

        $generatedOutput | Should -Contain 'ProjectsJson=["."]'
        $generatedOutput | Should -Contain 'ProjectDependenciesJson={".":[]}'
        $generatedOutput | Should -Contain 'BuildOrderJson=[{"projects":["."],"projectsCount":1,"buildDimensions":[{"buildMode":"Default","project":"."}]}]'
    }

    It 'loads two independent projects with no build modes set' {
        New-Item -Path "$baseFolder\Project1\.AL-Go\settings.json" -type File -Force
        New-Item -Path "$baseFolder\Project2\.AL-Go\settings.json" -type File -Force

        & $scriptPath `
            -baseFolder $baseFolder

        $generatedOutput = Get-Content $env:GITHUB_OUTPUT

        Write-Host $generatedOutput

        $generatedOutput | Should -Contain 'ProjectsJson=["Project1","Project2"]'
        $generatedOutput | Should -Contain 'ProjectDependenciesJson={"Project1":[],"Project2":[]}'
        $generatedOutput | Should -Contain 'BuildOrderJson=[{"projects":["Project1","Project2"],"projectsCount":2,"buildDimensions":[{"buildMode":"Default","project":"Project1"},{"buildMode":"Default","project":"Project2"}]}]'
    }

    It 'loads two independent projects with build modes set' {
        New-Item -Path "$baseFolder\Project1\.AL-Go\settings.json" -Value $(@{ buildModes = @("Default", "Clean") } | ConvertTo-Json ) -type File -Force
        New-Item -Path "$baseFolder\Project2\.AL-Go\settings.json" -Value $(@{ buildModes = @("Default") } | ConvertTo-Json ) -type File -Force

        & $scriptPath `
            -baseFolder $baseFolder

        $generatedOutput = Get-Content $env:GITHUB_OUTPUT

        Write-Host $generatedOutput

        $generatedOutput | Should -Contain 'ProjectsJson=["Project1","Project2"]'
        $generatedOutput | Should -Contain 'ProjectDependenciesJson={"Project1":[],"Project2":[]}'
        $generatedOutput | Should -Contain 'BuildOrderJson=[{"projects":["Project1","Project2"],"projectsCount":2,"buildDimensions":[{"buildMode":"Default","project":"Project1"},{"buildMode":"Clean","project":"Project1"},{"buildMode":"Default","project":"Project2"}]}]'
    }

    AfterEach {
        Remove-Item $env:GITHUB_OUTPUT -Force
        Remove-Item $baseFolder -Force -Recurse
    }
}
