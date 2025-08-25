Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'CalculateArtifactNames Action Tests' {

    BeforeAll {
        $actionName = "CalculateArtifactNames"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        $env:Settings = '{ "appBuild": 123, "repoVersion": "22.0", "appRevision": 0,"repoName": "AL-Go"}'
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'project', Justification = 'False positive.')]
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
        $env:GITHUB_HEAD_REF = "main"
        & $scriptPath `
                -project $project `
                -buildMode $buildMode

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain "AppsArtifactsName=ALGOProject-main-CleanApps-22.0.123.0"
        $generatedOutPut | Should -Contain "DependenciesArtifactsName=ALGOProject-main-CleanDependencies-22.0.123.0"
        $generatedOutPut | Should -Contain "TestAppsArtifactsName=ALGOProject-main-CleanTestApps-22.0.123.0"
        $generatedOutPut | Should -Contain "TestResultsArtifactsName=ALGOProject-main-CleanTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-main-CleanBcptTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "PageScriptingTestResultsArtifactsName=ALGOProject-main-CleanPageScriptingTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "PageScriptingTestResultDetailsArtifactsName=ALGOProject-main-CleanPageScriptingTestResultDetails-22.0.123.0"
        $generatedOutPut | Should -Contain "BuildOutputArtifactsName=ALGOProject-main-CleanBuildOutput-22.0.123.0"
        $generatedOutPut | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-main-CleanContainerEventLog-22.0.123.0"
        $generatedOutPut | Should -Contain "ErrorLogsArtifactsName=ALGOProject-main-CleanErrorLogs-22.0.123.0"
        $generatedOutPut | Should -Contain "BuildMode=Clean"

    }

    It 'should not include buildmode name in artifact name if buildmode is default' {
        $buildMode = "Default"
        $env:GITHUB_HEAD_REF = "main"
        & $scriptPath `
                -project $project `
                -buildMode $buildMode

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain "AppsArtifactsName=ALGOProject-main-Apps-22.0.123.0"
        $generatedOutPut | Should -Contain "DependenciesArtifactsName=ALGOProject-main-Dependencies-22.0.123.0"
        $generatedOutPut | Should -Contain "TestAppsArtifactsName=ALGOProject-main-TestApps-22.0.123.0"
        $generatedOutPut | Should -Contain "TestResultsArtifactsName=ALGOProject-main-TestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-main-BcptTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "PageScriptingTestResultsArtifactsName=ALGOProject-main-PageScriptingTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "PageScriptingTestResultDetailsArtifactsName=ALGOProject-main-PageScriptingTestResultDetails-22.0.123.0"
        $generatedOutPut | Should -Contain "BuildOutputArtifactsName=ALGOProject-main-BuildOutput-22.0.123.0"
        $generatedOutPut | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-main-ContainerEventLog-22.0.123.0"
        $generatedOutPut | Should -Contain "ErrorLogsArtifactsName=ALGOProject-main-ErrorLogs-22.0.123.0"
    }

    It 'should escape slashes and backslashes in artifact name' {
        $buildMode = "Default"
        $env:GITHUB_HEAD_REF = "releases/1.0"
        & $scriptPath `
                -project $project `
                -buildMode $buildMode

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain "AppsArtifactsName=ALGOProject-releases_1.0-Apps-22.0.123.0"
        $generatedOutPut | Should -Contain "DependenciesArtifactsName=ALGOProject-releases_1.0-Dependencies-22.0.123.0"
        $generatedOutPut | Should -Contain "TestAppsArtifactsName=ALGOProject-releases_1.0-TestApps-22.0.123.0"
        $generatedOutPut | Should -Contain "TestResultsArtifactsName=ALGOProject-releases_1.0-TestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-releases_1.0-BcptTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "PageScriptingTestResultsArtifactsName=ALGOProject-releases_1.0-PageScriptingTestResults-22.0.123.0"
        $generatedOutPut | Should -Contain "PageScriptingTestResultDetailsArtifactsName=ALGOProject-releases_1.0-PageScriptingTestResultDetails-22.0.123.0"
        $generatedOutPut | Should -Contain "BuildOutputArtifactsName=ALGOProject-releases_1.0-BuildOutput-22.0.123.0"
        $generatedOutPut | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-releases_1.0-ContainerEventLog-22.0.123.0"
        $generatedOutPut | Should -Contain "ErrorLogsArtifactsName=ALGOProject-releases_1.0-ErrorLogs-22.0.123.0"
    }

    It 'should use the specified suffix if provided' {
        $buildMode = "Default"
        $env:GITHUB_HEAD_REF  = "releases/1.0"
        $suffix = "Current"
        & $scriptPath `
                -project $project `
                -buildMode $buildMode `
                -suffix $suffix

        # In rare cases, when this test is run at the end of the day, the date will change between the time the script is run and the time the test is run.
        $currentDate = [DateTime]::UtcNow.ToString('yyyyMMdd')

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain "AppsArtifactsName=ALGOProject-releases_1.0-Apps-Current-$currentDate"
        $generatedOutPut | Should -Contain "DependenciesArtifactsName=ALGOProject-releases_1.0-Dependencies-Current-$currentDate"
        $generatedOutPut | Should -Contain "TestAppsArtifactsName=ALGOProject-releases_1.0-TestApps-Current-$currentDate"
        $generatedOutPut | Should -Contain "TestResultsArtifactsName=ALGOProject-releases_1.0-TestResults-Current-$currentDate"
        $generatedOutPut | Should -Contain "BcptTestResultsArtifactsName=ALGOProject-releases_1.0-BcptTestResults-Current-$currentDate"
        $generatedOutPut | Should -Contain "PageScriptingTestResultsArtifactsName=ALGOProject-releases_1.0-PageScriptingTestResults-Current-$currentDate"
        $generatedOutPut | Should -Contain "PageScriptingTestResultDetailsArtifactsName=ALGOProject-releases_1.0-PageScriptingTestResultDetails-Current-$currentDate"
        $generatedOutPut | Should -Contain "BuildOutputArtifactsName=ALGOProject-releases_1.0-BuildOutput-Current-$currentDate"
        $generatedOutPut | Should -Contain "ContainerEventLogArtifactsName=ALGOProject-releases_1.0-ContainerEventLog-Current-$currentDate"
        $generatedOutPut | Should -Contain "ErrorLogsArtifactsName=ALGOProject-releases_1.0-ErrorLogs-Current-$currentDate"
    }

    It 'handles special characters in project name' {
        $project = "ALGOProject_øåæ"
        $buildMode = "Default"
        $env:GITHUB_HEAD_REF = "releases/1.0"
        $suffix = "Current"
        & $scriptPath `
                -project $project `
                -buildMode $buildMode `
                -suffix $suffix

        # In rare cases, when this test is run at the end of the day, the date will change between the time the script is run and the time the test is run.
        $currentDate = [DateTime]::UtcNow.ToString('yyyyMMdd')

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain "AppsArtifactsName=ALGOProject_øåæ-releases_1.0-Apps-Current-$currentDate"
        $generatedOutPut | Should -Contain "DependenciesArtifactsName=ALGOProject_øåæ-releases_1.0-Dependencies-Current-$currentDate"
        $generatedOutPut | Should -Contain "TestAppsArtifactsName=ALGOProject_øåæ-releases_1.0-TestApps-Current-$currentDate"
        $generatedOutPut | Should -Contain "TestResultsArtifactsName=ALGOProject_øåæ-releases_1.0-TestResults-Current-$currentDate"
        $generatedOutPut | Should -Contain "BcptTestResultsArtifactsName=ALGOProject_øåæ-releases_1.0-BcptTestResults-Current-$currentDate"
        $generatedOutPut | Should -Contain "PageScriptingTestResultsArtifactsName=ALGOProject_øåæ-releases_1.0-PageScriptingTestResults-Current-$currentDate"
        $generatedOutPut | Should -Contain "PageScriptingTestResultDetailsArtifactsName=ALGOProject_øåæ-releases_1.0-PageScriptingTestResultDetails-Current-$currentDate"
        $generatedOutPut | Should -Contain "BuildOutputArtifactsName=ALGOProject_øåæ-releases_1.0-BuildOutput-Current-$currentDate"
        $generatedOutPut | Should -Contain "ContainerEventLogArtifactsName=ALGOProject_øåæ-releases_1.0-ContainerEventLog-Current-$currentDate"
        $generatedOutPut | Should -Contain "ErrorLogsArtifactsName=ALGOProject_øåæ-releases_1.0-ErrorLogs-Current-$currentDate"
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "AppsArtifactsName" = "Artifacts name for Apps"
            "PowerPlatformSolutionArtifactsName" = "Artifacts name for PowerPlatform Solution"
            "DependenciesArtifactsName" = "Artifacts name for Dependencies"
            "TestAppsArtifactsName" = "Artifacts name for TestApps"
            "TestResultsArtifactsName" = "Artifacts name for TestResults"
            "BcptTestResultsArtifactsName" = "Artifacts name for BcptTestResults"
            "PageScriptingTestResultsArtifactsName" = "Artifacts name for PageScriptingTestResults"
            "PageScriptingTestResultDetailsArtifactsName" = "Artifacts name for PageScriptingTestResultDetails"
            "BuildOutputArtifactsName" = "Artifacts name for BuildOutput"
            "ContainerEventLogArtifactsName" = "Artifacts name for ContainerEventLog"
            "ErrorLogsArtifactsName" = "Artifacts name for ErrorLogs"
            "BuildMode" = "Build mode used when building the artifacts"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }
}
