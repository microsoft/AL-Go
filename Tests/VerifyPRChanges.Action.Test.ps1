Describe 'VerifyPRChanges Action Tests' {

    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "..\Actions\VerifyPRChanges\VerifyPRChanges.ps1" -Resolve
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
                -prHeadRepository "fork/AL-Go" `
                -githubApiUrl "https://api.github.com" 
        } | Should Throw
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
                -prHeadRepository "fork/AL-Go" `
                -githubApiUrl "https://api.github.com" 
        } | Should Throw
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
                -prHeadRepository "fork/AL-Go" `
                -githubApiUrl "https://api.github.com" 
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "No changes to scripts, workflows or CODEOWNERS found." }
    }

    It "should always succeed if it is coming from the same repository" {
        Mock Write-Host {}
        & $scriptPath `
                -baseSHA "123" `
                -headSHA "456" `
                -prHeadRepository "microsoft/AL-Go" `
                -prBaseRepository "microsoft/AL-Go" `
                -githubApiUrl "https://api.github.com"
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Pull Request is from the same repository, skipping check." }
    }
}
