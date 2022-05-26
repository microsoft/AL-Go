$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Reloading the module
Get-Module AppHelper | Remove-Module -Force
Import-Module (Join-Path -path $here -ChildPath "..\Actions\CreateApp\AppHelper.psm1" -Resolve)
. (Join-Path -path $here -ChildPath "..\Actions\AL-Go-Helper.ps1" -Resolve)

Describe 'AppHelper.psm1 Tests' {
    It 'Confirm-IdRanges validates a valid PTE range' {
        $ids = Confirm-IdRanges -templateType "PTE" -idrange "50000..99999"
        $ids[0] | Should -EQ "50000"
        $ids[1] | Should -EQ "99999"
    }

    It 'Confirm-IdRanges throws on invalid PTE range' {
        { Confirm-IdRanges -templateType "PTE" -idrange "5000..50200" }   | Should -Throw
        { Confirm-IdRanges -templateType "PTE" -idrange "50000..5000" }   | Should -Throw
        { Confirm-IdRanges -templateType "PTE" -idrange "50100..50000" }  | Should -Throw
        { Confirm-IdRanges -templateType "PTE" -idrange "50100..100000" } | Should -Throw
    }

    It 'Confirm-IdRanges validates a valid AppSource app range' {
        $ids = Confirm-IdRanges -templateType "AppSource App" -idrange "100000..110000"
        $ids[0] | Should -EQ "100000"
        $ids[1] | Should -EQ "110000"
    }

    It '(Confirm-IdRanges) should throw on invalid AppSource app range' {
        { Confirm-IdRanges -templateType "AppSource app" -idrange "99999..110000" }   | Should -Throw
        { Confirm-IdRanges -templateType "AppSource app" -idrange "100000..1100" }   | Should -Throw
        { Confirm-IdRanges -templateType "AppSource app" -idrange "110000..100000" }  | Should -Throw
        { Confirm-IdRanges -templateType "AppSource app" -idrange "110000..1000000000000000000000" }  | Should -Throw
    }

    It 'Should create a new app by calling New-SampleApp' {
        New-SampleApp -destinationPath "$($TestDrive)\SampleApp" -name "SampleApp" -publisher "TestPublisher" -version "1.0.0.0" -idrange "50101", "50120" -sampleCode $true

        "$($TestDrive)\SampleApp" | Should -Exist
        "$($TestDrive)\SampleApp\app.json" | Should -Exist
        
        $appJson = Get-Content -Path "$($TestDrive)\SampleApp\app.json" | ConvertFrom-Json
        $appJson.name | Should -be "SampleApp"
        $appJson.publisher | Should -be "TestPublisher"
        $appJson.version | Should -be "1.0.0.0"
        $appJson.idRanges[0].from | Should -be "50101"
        $appJson.idRanges[0].to | Should -be "50120"

        "$($TestDrive)\SampleApp\HelloWorld.al" | Should -Exist
        "$($TestDrive)\SampleApp\HelloWorld.al" | Should -FileContentMatch "pageextension 50101 CustomerListExt extends"

        "$($TestDrive)\SampleApp\.vscode\launch.json" | Should -Exist
    }

    It 'Should create a new test app by calling New-SampleTestApp' {
        New-SampleTestApp -destinationPath "$($TestDrive)\TestPTE" -name "TestPTE" -publisher "TestPublisher" -version "1.0.0.0" -idrange "50101", "50120" -sampleCode $true

        "$($TestDrive)\TestPTE" | Should -Exist
        "$($TestDrive)\TestPTE\app.json" | Should -Exist
        
        $appJson = Get-Content -Path "$($TestDrive)\TestPTE\app.json" | ConvertFrom-Json
        $appJson.name | Should -be "TestPTE"
        $appJson.publisher | Should -be "TestPublisher"
        $appJson.version | Should -be "1.0.0.0"
        $appJson.idRanges[0].from | Should -be "50101"
        $appJson.idRanges[0].to | Should -be "50120"

        "$($TestDrive)\TestPTE\HelloWorld.Test.al" | Should -Exist
        "$($TestDrive)\TestPTE\HelloWorld.Test.al" | Should -FileContentMatch "codeunit 50101"

        "$($TestDrive)\TestPTE\.vscode\launch.json" | Should -Exist
    }
}
