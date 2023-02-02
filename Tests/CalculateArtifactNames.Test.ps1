Describe 'CalculateArtifactNames Action Tests' {

    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "..\Actions\CalculateArtifactNames\CalculateArtifactNames.ps1" -Resolve
        $settingsJson = '{ "appBuild": 123, "repoVersion": "22.0", "appRevision": 0,"repoName": "AL-GO"}'
        $project = "ALGOProject"
        $branchName = "main"
    }


    It 'should include buildmode name in artifact name if buildmode is not default' {
        $buildMode = "Clean"
        & $scriptPath `
                -settingsJson $settingsJson `
                -project $project `
                -buildMode $buildMode `
                -branchName $branchName `
                -runLocally
        
        $env:AppsArtifactsName | Should -Be "ALGOProject-main-CleanApps-22.0.123.0"
        $env:TestAppsArtifactsName | Should -Be "ALGOProject-main-CleanTestApps-22.0.123.0"
    }

    It 'should not include buildmode name in artifact name if buildmode is default' {
        $buildMode = "Default"
        & $scriptPath `
                -settingsJson $settingsJson `
                -project $project `
                -buildMode $buildMode `
                -branchName $branchName `
                -runLocally
        
        Write-Host "BuildMode - $($Env:BuildMode)"
        $env:AppsArtifactsName | Should -Be "ALGOProject-main-Apps-22.0.123.0"
        $env:TestAppsArtifactsName | Should -Be "ALGOProject-main-TestApps-22.0.123.0"
    }

}
