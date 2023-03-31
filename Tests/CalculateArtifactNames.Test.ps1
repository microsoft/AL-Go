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
        $generatedEnvVariables | Should -Contain "ThisBuildAppsArtifactsName=thisbuild-ALGOProject-CleanApps"
        $generatedEnvVariables | Should -Contain "ThisBuildTestAppsArtifactsName=thisbuild-ALGOProject-CleanTestApps"
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
        $generatedEnvVariables | Should -Contain "ThisBuildAppsArtifactsName=thisbuild-ALGOProject-Apps"
        $generatedEnvVariables | Should -Contain "ThisBuildTestAppsArtifactsName=thisbuild-ALGOProject-TestApps"
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
        $generatedEnvVariables | Should -Contain "ThisBuildAppsArtifactsName=thisbuild-ALGOProject-Apps"
        $generatedEnvVariables | Should -Contain "ThisBuildTestAppsArtifactsName=thisbuild-ALGOProject-TestApps"
        $generatedEnvVariables | Should -Contain "AppsArtifactsName=ALGOProject-releases_1.0-Apps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "DependenciesArtifactsName=ALGOProject-releases_1.0-Dependencies-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestAppsArtifactsName=ALGOProject-releases_1.0-TestApps-22.0.123.0"
        $generatedEnvVariables | Should -Contain "TestResultsArtifactsName=ALGOProject-releases_1.0-TestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-releases_1.0-BcptTestResults-22.0.123.0"
        $generatedEnvVariables | Should -Contain "BuildOutputArtifactsName=ALGOProject-releases_1.0-BuildOutput-22.0.123.0"
        $generatedEnvVariables | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-releases_1.0-ContainerEventLog-22.0.123.0"
    }

    It 'should use the specified suffix if provided' {
        $buildMode = "Default"
        $branchName = "releases/1.0"
        $suffix = "Current"
        & $scriptPath `
                -settingsJson $settingsJson `
                -project $project `
                -buildMode $buildMode `
                -branchName $branchName `
                -suffix $suffix

        # In rare cases, when this test is run at the end of the day, the date will change between the time the script is run and the time the test is run.
        $currentDate = [DateTime]::UtcNow.ToString('yyyyMMdd')
        
        $generatedEnvVariables = Get-Content $env:GITHUB_ENV
        $generatedEnvVariables | Should -Contain "ThisBuildAppsArtifactsName=thisbuild-ALGOProject-Apps"
        $generatedEnvVariables | Should -Contain "ThisBuildTestAppsArtifactsName=thisbuild-ALGOProject-TestApps"

        $env:GITHUB_ENV | Should -FileContentMatch "AppsArtifactsName=ALGOProject-releases_1.0-Apps-Current-$currentDate"
        $env:GITHUB_ENV | Should -FileContentMatch "DependenciesArtifactsName=ALGOProject-releases_1.0-Dependencies-Current-$currentDate"
        $env:GITHUB_ENV | Should -FileContentMatch "TestAppsArtifactsName=ALGOProject-releases_1.0-TestApps-Current-$currentDate"
        $env:GITHUB_ENV | Should -FileContentMatch "TestResultsArtifactsName=ALGOProject-releases_1.0-TestResults-Current-$currentDate"
        $env:GITHUB_ENV | Should -FileContentMatch "BcptTestResultsArtifactsName=ALGOProject-releases_1.0-BcptTestResults-Current-$currentDate"
        $env:GITHUB_ENV | Should -FileContentMatch "BuildOutputArtifactsName=ALGOProject-releases_1.0-BuildOutput-Current-$currentDate"
        $env:GITHUB_ENV | Should -FileContentMatch "ContainerEventLogArtifactsName=ALGOProject-releases_1.0-ContainerEventLog-Current-$currentDate"
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
            "ThisBuildAppsArtifactsName" = "Artifact name for apps being built in the current workflow run"
            "ThisBuildTestAppsArtifactsName" = "Artifact name for test apps being built in the current workflow run"
            "AppsArtifactsName" = "Artifacts name for Apps"
            "DependenciesArtifactsName" = "Artifacts name for Dependencies"
            "TestAppsArtifactsName" = "Artifacts name for TestApps"
            "TestResultsArtifactsName" = "Artifacts name for TestResults"
            "BcptTestResultsArtifactsName" = "Artifacts name for BcptTestResults"
            "BuildOutputArtifactsName" = "Artifacts name for BuildOutput"
            "ContainerEventLogArtifactsName" = "Artifacts name for ContainerEventLog"
            "BuildMode" = "Build mode used when building the artifacts"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }
}
