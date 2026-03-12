Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'VerifyPRChanges Action Tests' {

    BeforeAll {
        $actionName = "VerifyPRChanges"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'should fail if the PR is from a fork and changes a script' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename": "Scripts/BuildScript.ps1", "status": "modified"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and adds a script' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"Scripts/BuildScript.ps1", "status": "added"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and removes a script' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"Scripts/BuildScript.ps1","status":"removed"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and changes the CODEOWNERS file' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"CODEOWNERS","status":"modified"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and changes anything in the .github folder' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":".github/Settings.json","status":"modified"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and changes a yml file' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":".github/workflows/test.yaml","status":"modified"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should succeed if the PR is from a fork and changes an .al file' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"ALModule/Test.Codeunit.al","status":"modified"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

        Mock Write-Host {}
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Verification completed successfully." }
    }

    It 'should succeed if the PR is from a fork and adds an .al file' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"ALModule/Test.Codeunit.al","status":"added"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

        Mock Write-Host {}
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Verification completed successfully." }
    }

    It 'should succeed if the PR is from a fork and removes an .al file' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"ALModule/Test.Codeunit.al","status":"removed"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

        Mock Write-Host {}
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Verification completed successfully." }
    }

    It 'should fail if the PR is from a fork and changes anything in the .AL-Go folder' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 1 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '[{"filename":"app/.AL-Go/settings.json","status":"modified"}]' } } -ParameterFilter { $Uri -and $Uri -match "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and changes more than 3000 files' {
        Mock -CommandName Invoke-WebRequest -MockWith {  @{"Content" = '{ "changed_files": 5001 }' } } -ParameterFilter { $Uri -and $Uri -notmatch "/files"}

       {
        & $scriptPath `
                -prBaseRepository "microsoft/AL-Go" `
                -pullRequestId "123456" `
                -token "ABC"
        } | Should -Throw
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }
}
