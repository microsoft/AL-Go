Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe 'VerifyPRChanges Action Tests' {

    BeforeAll {
        $actionName = "VerifyPRChanges"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'should fail if the PR is from a fork and changes a script' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "Actions/AL-Go-Helper.ps1", "status": "modified" }] }'
        }
       { 
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and adds a script' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "Actions/AL-Go-Helper.ps1", "status": "added" }] }'
        }
       { 
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and removes a script' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "Actions/AL-Go-Helper.ps1", "status": "removed" }] }'
        }
       { 
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        } | Should -Throw
    }

    It 'should fail if the PR is from a fork and changes the CODEOWNERS file' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "CODEOWNERS", "status": "modified" }] }'
        }
       { 
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        } | Should -Throw
    }

    It 'should succeed if the PR is from a fork and changes an .al file' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "ALModule/Test.Codeunit.al", "status": "modified" }] }'
        }
        Mock Write-Host {}
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Verification completed successfully." }
    }

    It 'should succeed if the PR is from a fork and adds an .al file' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "ALModule/Test.Codeunit.al", "status": "added" }] }'
        }
        Mock Write-Host {}
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Verification completed successfully." }
    }

    It 'should succeed if the PR is from a fork and removes an .al file' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "ALModule/Test.Codeunit.al", "status": "removed" }] }'
        }
        Mock Write-Host {}
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com" `
                -token "ABC" 
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Verification completed successfully." }
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
