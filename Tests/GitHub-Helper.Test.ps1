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

        CompareSemVerStrs -semVerStr1 '1.0.0' -semVerStr2 '1.0.0' | Should -Be 0
        CompareSemVerStrs -semVerStr1 'v3.2.1' -semVerStr2 '3.2.1' | Should -Be 0
        CompareSemVerStrs -semVerStr1 '1.0.0' -semVerStr2 '1.0.0' | Should -Be 0
        CompareSemVerStrs -semVerStr1 '1.0.0' -semVerStr2 '1.0.1' | Should -Be -1
        CompareSemVerStrs -semVerStr1 '1.0.0' -semVerStr2 '1.1.0' | Should -Be -1
        CompareSemVerStrs -semVerStr1 '1.0.0' -semVerStr2 '2.0.0' | Should -Be -1
        CompareSemVerStrs -semVerStr1 '2.0.1' -semVerStr2 '2.0.0' | Should -Be 1
        CompareSemVerStrs -semVerStr1 '2.1.0' -semVerStr2 '2.0.0' | Should -Be 1
        CompareSemVerStrs -semVerStr1 '2.0.0' -semVerStr2 '20.0.0' | Should -Be -1
        CompareSemVerStrs -semVerStr1 '2.10.0' -semVerStr2 '2.1.0' | Should -Be 1
        CompareSemVerStrs -semVerStr1 '2.10.2' -semVerStr2 '2.10.20' | Should -Be -1
        CompareSemVerStrs -semVerStr1 '2.0.0' -semVerStr2 '2.0.0-alpha' | Should -Be 1
        CompareSemVerStrs -semVerStr1 '2.0.0-alpha' -semVerStr2 '2.0.0-beta' | Should -Be -1
        CompareSemVerStrs -semVerStr1 '1.2.3-alpha.1.2.3.beta' -semVerStr2 'v1.2.3-alpha.1.2.3.alpha' | Should -Be 1
    }
}
