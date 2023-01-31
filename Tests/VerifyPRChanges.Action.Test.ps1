Describe 'VerifyPRChanges Action Tests' {

    It 'should fail if the PR is from a fork and changes a script' {
        Mock -CommandName Invoke-WebRequest -MockWith { 
            '{ "files": [{ "filename": "Actions/AL-Go-Helper.ps1", "status": "modified" }] }'
        }
       { 
        C:\Users\aholstrup\Documents\Github\aholstrup\AL-Go\Actions\VerifyPRChanges\VerifyPRChanges.ps1 `
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
        C:\Users\aholstrup\Documents\Github\aholstrup\AL-Go\Actions\VerifyPRChanges\VerifyPRChanges.ps1 `
                -baseSHA "123" `
                -headSHA "456" `
                -prBaseRepository "microsoft/AL-Go" `
                -prHeadRepository "fork/AL-Go" `
                -githubApiUrl "https://api.github.com" 
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "No changes to scripts, workflows or CODEOWNERS found." }
    }

    It "should always succeed if it is coming from the same repository" {
        Mock Write-Host {}
        C:\Users\aholstrup\Documents\Github\aholstrup\AL-Go\Actions\VerifyPRChanges\VerifyPRChanges.ps1 -baseSHA "123" -headSHA "456" -prHeadRepository "microsoft/AL-Go" -prBaseRepository "microsoft/AL-Go" -githubApiUrl "https://api.github.com"
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "Pull Request is from the same repository, skipping check." }
    }
}
