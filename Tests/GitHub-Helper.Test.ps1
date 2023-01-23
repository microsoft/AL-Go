Describe "GitHub-Helper Tests" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
    }

    It 'SemVerStrToSemVerObj/SemVerObjToSemVerStr' {
        { SemVerStrToSemVerObj -semVerStr 'not semver' } | Should -Throw
        { SemVerStrToSemVerObj -semVerStr '' } | Should -Throw
        { SemVerStrToSemVerObj -semVerStr 'v1.2' } | Should -Throw
        { SemVerStrToSemVerObj -semVerStr '1.2' } | Should -Throw

        SemVerStrToSemVerObj -semVerStr 'v1.2.3' | SemVerObjToSemVerStr | Should -Be 'v1.2.3'
        SemVerStrToSemVerObj -semVerStr '1.2.3' | SemVerObjToSemVerStr | Should -Be '1.2.3'
        SemVerStrToSemVerObj -semVerStr '1.2.0' | SemVerObjToSemVerStr | Should -Be '1.2.0'
        SemVerStrToSemVerObj -semVerStr 'v1.2' -allowMajorMinorOnly | SemVerObjToSemVerStr | Should -Be 'v1.2.0'
        SemVerStrToSemVerObj -semVerStr '1.2' -allowMajorMinorOnly | SemVerObjToSemVerStr | Should -Be '1.2.0'
        SemVerStrToSemVerObj -semVerStr 'v1.2.3-alpha.1' -allowMajorMinorOnly | SemVerObjToSemVerStr | Should -Be 'v1.2.3-alpha.1'
        SemVerStrToSemVerObj -semVerStr 'v1.2.3-alpha.1.2.3.beta' -allowMajorMinorOnly | SemVerObjToSemVerStr | Should -Be 'v1.2.3-alpha.1.2.3.beta'
        SemVerStrToSemVerObj -semVerStr 'v1.2-beta' -allowMajorMinorOnly | SemVerObjToSemVerStr | Should -Be 'v1.2.0-beta'
        SemVerStrToSemVerObj -semVerStr 'v1.2-beta-1' -allowMajorMinorOnly | SemVerObjToSemVerStr | Should -Be 'v1.2.0-beta-1'

        { SemVerStrToSemVerObj -semVerStr 'v1.2.3-alpha.1.2.3.beta.5' } | Should -Throw
        { SemVerStrToSemVerObj -semVerStr 'v1.2.3-alpha.1.2.zzzz.beta.5' } | Should -Throw

    }
}
