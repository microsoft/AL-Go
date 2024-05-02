Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Build Power Platform Settings Action Tests" {
    BeforeAll {
        $actionName = "BuildPowerPlatform"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'testDataPath', Justification = 'False positive.')]
        $testDataPath = Join-Path $PSScriptRoot "_TestData-PowerPlatform/*"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'testDataTempPath', Justification = 'False positive.')]
        $testDataTempPath = Join-Path $PSScriptRoot "_TestData-PowerPlatform_temp"

        Invoke-Expression $actionScript
    }

    BeforeEach {
        New-Item -Path $testDataTempPath -ItemType Directory -Force | Out-Null
        Copy-Item -Path $testDataPath -Destination $testDataTempPath -Recurse -Force
    }

    AfterEach {
        Remove-Item -Path $testDataTempPath -Recurse -Force
    }

    It 'Updates the solution file' {
        # The old version is hardcoded in the test data
        $oldVersionString = "1.0.0.0"

        $newBuildString = "222"
        $newRevisionString = "999"
        $newVersionString = "1.0.$newBuildString.$newRevisionString"

        $solutionPath = "$testDataTempPath/StandardSolution";

        $testSolutionFileBeforeTest = [xml](Get-Content -Encoding UTF8 -Path (Join-Path $solutionPath 'other/Solution.xml'))
        $versionNode = $testSolutionFileBeforeTest.SelectSingleNode("//Version")
        $versionNodeText = $versionNode.'#text'
        $versionNodeText | Should -Not -BeNullOrEmpty
        $versionNodeText | Should -Contain $oldVersionString

        BuildPowerPlatform -solutionFolder $solutionPath -appBuild $newBuildString -appRevision $newRevisionString

        $testSolutionFileAfterTest = [xml](Get-Content -Encoding UTF8 -Path (Join-Path $solutionPath 'other/Solution.xml'))
        $versionNode = $testSolutionFileAfterTest.SelectSingleNode("//Version")
        $versionNodeText = $versionNode.'#text'
        $versionNodeText | Should -Not -BeNullOrEmpty
        $versionNodeText | Should -Not -Contain $oldVersionString
        $versionNodeText | Should -Contain $newVersionString
    }

    It 'Updates the Power App connections' {
        # note: The old company name and environment name are hardcoded in the test data
        $oldCompanyName = "TestCompanyId"
        $oldEnvironmentName = "TestEnvironmentName"

        $newCompanyName = "NewCompanyName"
        $newEnvironmentName = "NewEnvironmentName"

        $solutionPath = "$testDataTempPath/StandardSolution";

        # Check file content before running the script
        # NOTE: There are multiple connection files in the test data, but we only check one of them as a smoke test
        $connectionFileContent = [string](Get-Content -Encoding UTF8 -Path (Join-Path $solutionPath 'CanvasApps/src/TestApp/Connections/Connections.json'))
        $connectionFileContent | Should -Not -BeNullOrEmpty
        $connectionFileContent | Should -Match $oldCompanyName
        $connectionFileContent | Should -Match $oldEnvironmentName
        $connectionFileContent | Should -Not -Match $newCompanyName
        $connectionFileContent | Should -Not -Match $newEnvironmentName

        $workflowFileContent = [string](Get-Content -Encoding UTF8 -Path (Join-Path $solutionPath 'Workflows/TestWorkflow-ABA81736-12D9-ED11-A7C7-000D3A991110.json'))
        $workflowFileContent | Should -Not -BeNullOrEmpty
        $workflowFileContent | Should -Match $oldCompanyName
        $workflowFileContent | Should -Match $oldEnvironmentName
        $workflowFileContent | Should -Not -Match $newCompanyName
        $workflowFileContent | Should -Not -Match $newEnvironmentName

        # Run the script
        BuildPowerPlatform -solutionFolder $solutionPath -CompanyId $newCompanyName -EnvironmentName $newEnvironmentName

        # Check file content after running the script
        $connectionFileContent = [string](Get-Content -Encoding UTF8 -Path (Join-Path $solutionPath 'CanvasApps/src/TestApp/Connections/Connections.json'))
        $connectionFileContent | Should -Not -BeNullOrEmpty
        $connectionFileContent | Should -Not -Match $oldCompanyName
        $connectionFileContent | Should -Not -Match $oldEnvironmentName
        $connectionFileContent | Should -Match $newCompanyName
        $connectionFileContent | Should -Match $newEnvironmentName

        $workflowFileContent = [string](Get-Content -Encoding UTF8 -Path (Join-Path $solutionPath 'Workflows/TestWorkflow-ABA81736-12D9-ED11-A7C7-000D3A991110.json'))
        $workflowFileContent | Should -Not -BeNullOrEmpty
        $workflowFileContent | Should -Not -Match $oldCompanyName
        $workflowFileContent | Should -Not -Match $oldEnvironmentName
        $workflowFileContent | Should -Match $newCompanyName
        $workflowFileContent | Should -Match $newEnvironmentName
    }

    It 'Works with PowerApp Only' {
        $solutionPath = "$testDataTempPath\PowerAppOnlySolution";

        # Run the script
        BuildPowerPlatform -solutionFolder $solutionPath -CompanyId "NewCompanyName" -EnvironmentName "NewEnvironmentName"
    }

    It 'Works with Flow only solution' {
        $solutionPath = "$testDataTempPath/FlowOnlySolution";
        BuildPowerPlatform -solutionFolder $solutionPath -CompanyId "NewCompanyName" -EnvironmentName "NewEnvironmentName"
    }
}
