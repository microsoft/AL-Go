Get-Module Github-Helper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\Github-Helper.psm1' -Resolve)
Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
Get-Module TelemetryHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\TelemetryHelper.psm1')

Describe 'CreateReleaseNotes Tests' {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1")

        function TrackTrace {}
        function TrackException {}

        $actionName = "CreateReleaseNotes"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        $scriptPath = Join-Path $scriptRoot $scriptName
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
            "ReleaseNotes" = "Release note generated based on the changes"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }
    
    It 'Confirms that right functions are called' {
        Mock GetLatestRelease { return "{""tag_name"" : ""1.0.0.0""}" | ConvertFrom-Json } 
        Mock GetReleaseNotes  {return "{
            ""name"": ""tagname"",
            ""body"": ""Mocked notes""
        }"}
        Mock DownloadAndImportBcContainerHelper  {}
        Mock CreateScope  {}

        . $scriptPath -token "" -actor "" -workflowToken "" -tag_name "1.0.5" -parentTelemetryScopeJson "{}"
    
        Should -Invoke -CommandName GetLatestRelease -Exactly -Times 1 
        Should -Invoke -CommandName GetReleaseNotes -Exactly -Times 1 -ParameterFilter { $tag_name -eq "1.0.5" -and $previous_tag_name -eq "1.0.0.0" }

        $releaseNotes | Should -Be "Mocked notes"
    }

    It 'Confirm right parameters are passed' {
        Mock GetLatestRelease { return $null } 
        Mock GetReleaseNotes  {return "{
            ""name"": ""tagname"",
            ""body"": ""Mocked notes""
        }"}
        Mock DownloadAndImportBcContainerHelper  {}
        Mock CreateScope  {}

        . $scriptPath -token "" -actor "" -workflowToken "" -tag_name "1.0.5" -parentTelemetryScopeJson "{}"
    
        Should -Invoke -CommandName GetLatestRelease -Exactly -Times 1 
        Should -Invoke -CommandName GetReleaseNotes -Exactly -Times 1 -ParameterFilter { $tag_name -eq "1.0.5" -and $previous_tag_name -eq "" }

        $releaseNotes | Should -Be "Mocked notes"
    }
}
