Describe 'CalculateArtifactNames Action Tests' {

    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "..\Actions\DetermineDeliveryTargets\DetermineDeliveryTargets.ps1" -Resolve
    }

    AfterEach {
        if ($env:NugetContext) {
            [Environment]::SetEnvironmentVariable("NugetContext",$null)
        }
    }


    It 'should add Nuget as a DeliveryTarget if NugetContext is set' {
        [System.Environment]::SetEnvironmentVariable("NugetContext", [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("NugetPAT")))

        $projectsJson = '["Modules"]'
        $settingsJson = '{ "DeliverToNuget": { "Branches": ["main"]}}'
        $workspace = Join-Path $PSScriptRoot "..\" -Resolve
        $type = "PTE"
        $refName = "main"
        
        Mock Write-Host {}
        & $scriptPath `
                -projectsJson $projectsJson `
                -settingsJson $settingsJson `
                -workspace $workspace `
                -type $type `
                -refName $refName `
                -runLocally
        
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq 'Assigning ["NuGet"] to DeliveryTargetsJson' }
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq 'Assigning 1 to DeliveryTargetCount' }
    }

    It 'should not add any delivery targets if no context is set ' {
        $projectsJson = '["Modules"]'
        $settingsJson = '{}'
        $workspace = Join-Path $PSScriptRoot "..\" -Resolve
        $type = "PTE"
        $refName = "main"
        
        Mock Write-Host {}
        & $scriptPath `
                -projectsJson $projectsJson `
                -settingsJson $settingsJson `
                -workspace $workspace `
                -type $type `
                -refName $refName `
                -runLocally
        
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq 'Assigning [] to DeliveryTargetsJson' }
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq 'Assigning 0 to DeliveryTargetCount' }
    }
}
