Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe 'CalculateArtifactNames Action Tests' {

    BeforeAll {
        $actionName = "CalculateArtifactNames"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        $settingsJson = '{ "appBuild": 123, "repoVersion": "22.0", "appRevision": 0,"repoName": "AL-GO"}'
        $project = "ALGOProject"
    }

    BeforeEach {
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_ENV = [System.IO.Path]::GetTempFileName()

        Write-Host $env:GITHUB_OUTPUT
        Write-Host $env:GITHUB_ENV
    }


    It 'should include buildmode name in artifact name if buildmode is not default' {
        $buildMode = "Clean"
        $branchName = "main"
        & $scriptPath `
                -settingsJson $settingsJson `
                -project $project `
                -buildMode $buildMode `
                -branchName $branchName
        
        $generatedEnvVariables = Get-Content $env:GITHUB_ENV
        $generatedEnvVariables | Should -Contain "AppsArtifactsName=ALGOProject-main-CleanApps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "DependenciesArtifactsName=ALGOProject-main-CleanDependencies-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestAppsArtifactsName=ALGOProject-main-CleanTestApps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestResultsArtifactsName=ALGOProject-main-CleanTestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-main-CleanBcptTestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BuildOutputArtifactsName=ALGOProject-main-CleanBuildOutput-22.0.123.0"
        $generatedEnvVariables | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-main-CleanContainerEventLog-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BuildMode=Clean"

    }

    It 'should not include buildmode name in artifact name if buildmode is default' {
        $buildMode = "Default"
        $branchName = "main"
        & $scriptPath `
                -settingsJson $settingsJson `
                -project $project `
                -buildMode $buildMode `
                -branchName $branchName
        
        $generatedEnvVariables = Get-Content $env:GITHUB_ENV
        $generatedEnvVariables | Should -Contain "AppsArtifactsName=ALGOProject-main-Apps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "DependenciesArtifactsName=ALGOProject-main-Dependencies-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestAppsArtifactsName=ALGOProject-main-TestApps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestResultsArtifactsName=ALGOProject-main-TestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-main-BcptTestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BuildOutputArtifactsName=ALGOProject-main-BuildOutput-22.0.123.0"
        $generatedEnvVariables | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-main-ContainerEventLog-22.0.123.0"
    }

    It 'should escape slashes and backslashes in artifact name' {
        $buildMode = "Default"
        $branchName = "releases/1.0"
        & $scriptPath `
                -settingsJson $settingsJson `
                -project $project `
                -buildMode $buildMode `
                -branchName $branchName
        
        $generatedEnvVariables = Get-Content $env:GITHUB_ENV
        $generatedEnvVariables | Should -Contain "AppsArtifactsName=ALGOProject-releases_1.0-Apps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "DependenciesArtifactsName=ALGOProject-releases_1.0-Dependencies-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestAppsArtifactsName=ALGOProject-releases_1.0-TestApps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestResultsArtifactsName=ALGOProject-releases_1.0-TestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-releases_1.0-BcptTestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BuildOutputArtifactsName=ALGOProject-releases_1.0-BuildOutput-22.0.123.0"
        $generatedEnvVariables | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-releases_1.0-ContainerEventLog-22.0.123.0"
    }


    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }
}
