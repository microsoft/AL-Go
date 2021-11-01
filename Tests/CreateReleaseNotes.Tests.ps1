$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = (Join-Path -path $here -ChildPath "..\Actions\CreateReleaseNotes\CreateReleaseNotes.ps1" -Resolve)
Get-Module module | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\Github-Helper.psm1' -Resolve)

Describe 'CreateReleaseNotes Tests' {
    
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
