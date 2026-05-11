Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "CreateApp Action Tests" {
    BeforeAll {
        $actionName = "CreateApp"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    # Call action

    It 'Should find Performance Toolkit sample app with <Casing> directory casing' -TestCases @(
        @{ Casing = 'PascalCase'; Dirs = @('Applications', 'TestFramework', 'performancetoolkit') }
        @{ Casing = 'lowercase';  Dirs = @('applications', 'testframework', 'performancetoolkit') }
    ) {
        param($Casing, $Dirs)
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        try {
            $sampleAppDir = Join-Path $tempDir $Dirs[0] $Dirs[1] $Dirs[2]
            New-Item -Path $sampleAppDir -ItemType Directory -Force | Out-Null
            $sampleAppFile = Join-Path $sampleAppDir "Microsoft_Performance Toolkit Samples.app"
            Set-Content -Path $sampleAppFile -Value "dummy"

            # Use the same lookup logic as in CreateApp.ps1
            $result = Get-ChildItem -Path $tempDir -Filter "Microsoft_Performance Toolkit Samples.app" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Be $sampleAppFile
        }
        finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
