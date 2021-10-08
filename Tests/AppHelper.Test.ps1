$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Reloading the module
Get-Module AppHelper | Remove-Module -Force
Import-Module (Join-Path -path $here -ChildPath "..\Actions\CreateApp\AppHelper.psm1" -Resolve)

Describe 'AppHelper.psm1 Tests' {
    It 'ValidateIdRanges validates a valid PTE range' {
        $ids = ValidateIdRanges -templateType "PTE" -idrange "50000..99999"
        $ids[0] | Should -EQ "50000"
        $ids[1] | Should -EQ "99999"
    }

    It 'ValidateIdRanges throws on invalid PTE range' {
        { ValidateIdRanges -templateType "PTE" -idrange "5000..50200" }   | Should -Throw
        { ValidateIdRanges -templateType "PTE" -idrange "50000..5000" }   | Should -Throw
        { ValidateIdRanges -templateType "PTE" -idrange "50100..50000" }  | Should -Throw
        { ValidateIdRanges -templateType "PTE" -idrange "50100..100000" } | Should -Throw
    }

    It 'ValidateIdRanges validates a valid AppSource app range' {
        $ids = ValidateIdRanges -templateType "AppSource App" -idrange "100000..110000"
        $ids[0] | Should -EQ "100000"
        $ids[1] | Should -EQ "110000"
    }

    It 'ValidateIdRanges throws on invalid AppSource app range' {
        { ValidateIdRanges -templateType "AppSource app" -idrange "99999..110000" }   | Should -Throw
        { ValidateIdRanges -templateType "AppSource app" -idrange "100000..1100" }   | Should -Throw
        { ValidateIdRanges -templateType "AppSource app" -idrange "110000..100000" }  | Should -Throw
        { ValidateIdRanges -templateType "AppSource app" -idrange "110000..1000000000000000000000" }  | Should -Throw
    }
}