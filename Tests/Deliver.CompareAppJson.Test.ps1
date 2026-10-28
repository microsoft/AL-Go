Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Deliver Module - ConvertTo-ComparableAppJson Tests" {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot "../Actions/Deliver/Deliver.psm1" -Resolve) -DisableNameChecking -Force

        function New-TestAppJson {
            Param(
                [string] $version = '26.0.2.605',
                [string] $dependencyVersion = '26.0.2.0'
            )
            return [PSCustomObject]@{
                id           = '37a92ffe-4b22-4228-8805-02635eac97ee'
                name         = 'Test app for BHG Foundation App'
                publisher    = 'Bunker Holding Group'
                version      = $version
                dependencies = @(
                    [PSCustomObject]@{
                        id        = '7ce0b65f-bc3e-497b-95bf-c7538ad8a5e8'
                        name      = 'BHG Foundation App'
                        publisher = 'Bunker Holding Group'
                        version   = $dependencyVersion
                    }
                )
            }
        }
    }

    It 'treats apps that only differ in the version revision as identical' {
        $new = ConvertTo-ComparableAppJson -AppJson (New-TestAppJson -version '26.0.2.605')
        $old = ConvertTo-ComparableAppJson -AppJson (New-TestAppJson -version '26.0.2.603')

        $new | Should -BeExactly $old
    }

    It 'treats apps with a different major, minor or build version as different' -TestCases @(
        @{ oldVersion = '25.0.2.603' }
        @{ oldVersion = '26.1.2.603' }
        @{ oldVersion = '26.0.1.603' }
    ) {
        param($oldVersion)

        $new = ConvertTo-ComparableAppJson -AppJson (New-TestAppJson -version '26.0.2.605')
        $old = ConvertTo-ComparableAppJson -AppJson (New-TestAppJson -version $oldVersion)

        $new | Should -Not -BeExactly $old
    }

    It 'treats apps with a different dependency version as different' {
        $new = ConvertTo-ComparableAppJson -AppJson (New-TestAppJson -dependencyVersion '26.0.2.0')
        $old = ConvertTo-ComparableAppJson -AppJson (New-TestAppJson -dependencyVersion '25.8.1.0')

        $new | Should -Not -BeExactly $old
    }

    It 'does not modify the app.json passed in' {
        $appJson = New-TestAppJson -version '26.0.2.605'

        ConvertTo-ComparableAppJson -AppJson $appJson | Out-Null

        $appJson.version | Should -BeExactly '26.0.2.605'
    }

    It 'handles an app.json without a version' {
        $appJson = [PSCustomObject]@{ id = '37a92ffe-4b22-4228-8805-02635eac97ee'; name = 'No version' }

        { ConvertTo-ComparableAppJson -AppJson $appJson } | Should -Not -Throw
    }
}
