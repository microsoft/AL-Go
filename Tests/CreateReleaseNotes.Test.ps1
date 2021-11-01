Get-Module Github-Helper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\Github-Helper.psm1' -Resolve)
Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')

Describe 'CreateReleaseNotes Tests' {
    BeforeAll {
        $actionName = "CreateReleaseNotes"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $PSScriptRoot $scriptName
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
            "contents" = "write"
            "pull-requests" = "write"
        }
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }
    
    It 'Confirms that right functions are called' {
        Mock GetLatestRelease { return "{""tag_name"" : ""1.0.0.0""}" | ConvertFrom-Json } 
        Mock GetReleaseNotes  {return "Mocked notes"}
    
        . $scriptPath -token "" -actor "" -workflowToken "" -tag_name "1.0.0.5"
    
        Should -Invoke -CommandName GetLatestRelease -Exactly -Times 1 
        Should -Invoke -CommandName GetReleaseNotes -Exactly -Times 1 -ParameterFilter { $tag_name -eq "1.0.0.5" -and $previous_tag_name -eq "1.0.0.0" }

        $releaseNotes | Should -Be "Mocked notes"
    }

    It 'Confirm right parameters are passed' {
        Mock GetLatestRelease { return ConvertTo-Json @{} } 
        Mock GetReleaseNotes  {return "Mocked notes"}
    
        . $scriptPath -token "" -actor "" -workflowToken "" -tag_name "1.0.0.5"
    
        Should -Invoke -CommandName GetLatestRelease -Exactly -Times 1 
        Should -Invoke -CommandName GetReleaseNotes -Exactly -Times 1 -ParameterFilter { $tag_name -eq "1.0.0.5" -and $previous_tag_name -eq "" }

        $releaseNotes | Should -Be "Mocked notes"
    }

    It 'Confirm when throws' {
        Mock GetLatestRelease { throw "Exception" } 
        Mock GetReleaseNotes  {return "Mocked notes"}
    
        . $scriptPath -token "" -actor "" -workflowToken "" -tag_name "1.0.0.5"
    
        Should -Invoke -CommandName GetLatestRelease -Exactly -Times 1 

        $releaseNotes | Should -Be ""
    }
}
