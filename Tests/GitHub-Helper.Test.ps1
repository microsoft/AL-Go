Get-Module Github-Helper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\Github-Helper.psm1' -Resolve)

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

    It 'GetLatestRelease handles releases/26.x branch' {
        # Mock GetReleases to return a list of releases (using -ModuleName to mock within the module)
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '26.3.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '26.2.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.1.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.0.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/26.x branch - should find the latest 26.x release (26.3.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26.x'
        $result.tag_name | Should -Be '26.3.0'

        # Test releases/26 branch - should find the latest 26.x release (26.3.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26'
        $result.tag_name | Should -Be '26.3.0'

        # Test releases/25 branch - should find the latest 25.x release (25.1.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/25'
        $result.tag_name | Should -Be '25.1.0'
    }

    It 'GetLatestRelease handles releases/26.3 branch (major.minor)' {
        # Mock GetReleases to return a list of releases
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '26.3.5'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '26.3.4'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '26.2.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.1.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/26.3 branch - should find the latest 26.3.x release (26.3.5)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26.3'
        $result.tag_name | Should -Be '26.3.5'
    }

    It 'GetLatestRelease handles main branch (non-release branch)' {
        # Mock GetReleases to return a list of releases
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '26.3.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.1.0'; prerelease = $false; draft = $false }
            )
        }

        # Test main branch - should return the latest overall release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'main'
        $result.tag_name | Should -Be '26.3.0'
    }

    It 'GetLatestRelease returns null when no matching release found' {
        # Mock GetReleases to return a list of releases
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '25.0.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '24.0.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/26.x branch - no 26.x releases exist
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26.x'
        $result | Should -Be $null
    }

    It 'GetLatestRelease handles release/26.x branch (singular form)' {
        # Mock GetReleases to return a list of releases
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '26.3.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.1.0'; prerelease = $false; draft = $false }
            )
        }

        # Test release/26.x branch (singular form) - should also work
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'release/26.x'
        $result.tag_name | Should -Be '26.3.0'
    }
}
