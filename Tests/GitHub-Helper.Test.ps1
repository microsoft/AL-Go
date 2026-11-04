Get-Module Github-Helper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot '..\Actions\Github-Helper.psm1' -Resolve)

Describe "FindLatestSuccessfulCICDRun" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')

        function NewCommit {
            param([string] $sha, [string[]] $parents = @(), [int] $daysAgo = 0)
            @{
                sha = $sha
                committer = @{ date = [DateTime]::UtcNow.AddDays(-$daysAgo).ToString('o') }
                parents = @($parents | ForEach-Object { @{ sha = $_ } })
            }
        }
    }

    BeforeEach {
        $script:branchHead = ''
        $script:commits = @{}
        $script:runs = @{}
        Mock Write-Host -ModuleName Github-Helper {}
        Mock Start-Sleep -ModuleName Github-Helper {}
        Mock CheckBuildJobsInWorkflowRun -ModuleName Github-Helper { $false }
        Mock InvokeWebRequest -ModuleName Github-Helper {
            if ($uri -match '/branches/') {
                return @{ Content = (@{ commit = @{ sha = $script:branchHead } } | ConvertTo-Json -Depth 10) }
            }
            if ($uri -match '/git/commits/(?<sha>[^/?]+)$') {
                return @{ Content = ($script:commits[$Matches.sha] | ConvertTo-Json -Depth 10) }
            }
            if ($uri -match '/actions/runs\?.*head_sha=(?<sha>[^&]+)') {
                $runList = @()
                if ($script:runs.ContainsKey($Matches.sha)) { $runList = @($script:runs[$Matches.sha]) }
                return @{ Content = (@{ workflow_runs = $runList } | ConvertTo-Json -Depth 10) }
            }
            throw "Unexpected request: $uri"
        }
    }

    BeforeAll {
        function NewCommit {
            param([string] $sha, [string[]] $parents = @(), [int] $daysAgo = 0)
            @{
                sha = $sha
                committer = @{ date = [DateTime]::UtcNow.AddDays(-$daysAgo).ToString('o') }
                parents = @($parents | ForEach-Object { @{ sha = $_ } })
            }
        }
    }

    It 'returns the CI/CD run of the branch head without walking further' {
        $script:branchHead = 'c3'
        $script:commits['c3'] = NewCommit 'c3' @('c2')
        $script:runs['c3'] = @(@{ id = 42; head_sha = 'c3'; name = ' CI/CD'; conclusion = 'success'; created_at = '2026-10-20T10:00:00Z' })

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'releases/29.x' -token 'secret-token' -retention 7)

        $result | Should -HaveCount 2
        $result[0] | Should -Be 42
        $result[1] | Should -BeExactly 'c3'
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 1 -Exactly -ParameterFilter { $uri -like '*/repos/test/repo/branches/releases/29.x' }
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 1 -Exactly -ParameterFilter {
            $uri -like '*/repos/test/repo/actions/runs?*head_sha=c3*' -and $uri -like '*branch=releases%2F29.x*' -and $uri -like '*status=completed*' -and $uri -like '*exclude_pull_requests=true*' -and $uri -like '*created=%3E*'
        }
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $uri -like '*/git/commits/*' }
        Should -Invoke CheckBuildJobsInWorkflowRun -ModuleName Github-Helper -Times 0 -Exactly
        Should -Invoke Write-Host -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { "$Object" -like '*secret-token*' }
    }

    It 'walks only the first parent and skips cancelled and unrelated runs' {
        $script:branchHead = 'c4'
        $script:commits['c4'] = NewCommit 'c4' @('c3', 'feature1')
        $script:commits['c3'] = NewCommit 'c3' @('c2')
        $script:commits['c2'] = NewCommit 'c2' @('c1')
        $script:runs['c4'] = @(
            @{ id = 50; head_sha = 'c4'; name = 'Other'; conclusion = 'success'; created_at = '2026-10-20T10:05:00Z' },
            @{ id = 49; head_sha = 'c4'; name = ' CI/CD'; conclusion = 'cancelled'; created_at = '2026-10-20T10:00:00Z' }
        )
        $script:runs['c3'] = @(@{ id = 48; head_sha = 'c3'; name = 'CI/CD'; conclusion = 'failure'; created_at = '2026-10-19T10:00:00Z' })
        $script:runs['c2'] = @(@{ id = 47; head_sha = 'c2'; name = ' CI/CD '; conclusion = 'failure'; created_at = '2026-10-18T10:00:00Z' })
        Mock CheckBuildJobsInWorkflowRun -ModuleName Github-Helper { $true } -ParameterFilter { $workflowRunId -eq '47' }

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7)

        $result | Should -HaveCount 2
        $result[0] | Should -Be 47
        $result[1] | Should -BeExactly 'c2'
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $uri -like '*feature1*' }
        Should -Invoke CheckBuildJobsInWorkflowRun -ModuleName Github-Helper -Times 2 -Exactly
        Should -Invoke CheckBuildJobsInWorkflowRun -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $workflowRunId -in @('49', '50') }
    }

    It 'selects the newest eligible run when a commit has several' {
        $script:branchHead = 'c1'
        $script:commits['c1'] = NewCommit 'c1'
        $script:runs['c1'] = @(
            @{ id = 10; head_sha = 'c1'; name = 'CI/CD'; conclusion = 'success'; created_at = '2026-10-01T10:00:00Z' },
            @{ id = 11; head_sha = 'c1'; name = 'CI/CD'; conclusion = 'success'; created_at = '2026-10-02T10:00:00Z' }
        )

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7)

        $result[0] | Should -Be 11
    }

    It 'checks the first commit older than the retention and stops there' {
        $script:branchHead = 'c2'
        $script:commits['c2'] = NewCommit 'c2' @('c1')
        $script:commits['c1'] = NewCommit 'c1' @('c0') -daysAgo 10

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7)

        $result | Should -HaveCount 2
        $result[0] | Should -Be 0
        $result[1] | Should -BeExactly ''
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 1 -Exactly -ParameterFilter { $uri -like '*head_sha=c1*' }
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $uri -like '*c0*' }
    }

    It 'finds a recent run on a head commit that is older than the retention' {
        $script:branchHead = 'c1'
        $script:commits['c1'] = NewCommit 'c1' @('c0') -daysAgo 30
        $script:runs['c1'] = @(@{ id = 5; head_sha = 'c1'; name = 'CI/CD'; conclusion = 'success'; created_at = '2026-10-20T10:00:00Z' })

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7)

        $result[0] | Should -Be 5
    }

    It 'returns zero and an empty SHA at the root commit' {
        $script:branchHead = 'c1'
        $script:commits['c1'] = NewCommit 'c1'

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7)

        $result | Should -HaveCount 2
        $result[0] | Should -Be 0
        $result[1] | Should -BeExactly ''
        Should -Invoke Start-Sleep -ModuleName Github-Helper -Times 0 -Exactly
    }

    It 'propagates request failures rather than returning a missing baseline' {
        Mock InvokeWebRequest -ModuleName Github-Helper { throw 'Request failed' }

        { FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7 } | Should -Throw 'Request failed'

        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 1 -Exactly
    }

    It 'uses the specified api_url instead of GITHUB_API_URL for commits, runs and jobs (e.g. local development environment)' {
        $originalApiUrl = $ENV:GITHUB_API_URL
        try {
            Remove-Item Env:GITHUB_API_URL -ErrorAction SilentlyContinue
            $script:branchHead = 'c1'
            $script:commits['c1'] = NewCommit 'c1'
            $script:runs['c1'] = @(@{ id = 42; head_sha = 'c1'; name = 'CI/CD'; conclusion = 'failure'; created_at = '2026-10-20T10:00:00Z' })
            Mock CheckBuildJobsInWorkflowRun -ModuleName Github-Helper { $true }

            $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7 -api_url 'https://api.contoso.ghe.com')

            $result[0] | Should -Be 42
            Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $uri -notlike 'https://api.contoso.ghe.com/repos/test/repo/*' }
            Should -Invoke CheckBuildJobsInWorkflowRun -ModuleName Github-Helper -Times 1 -Exactly -ParameterFilter { $api_url -eq 'https://api.contoso.ghe.com' }
        }
        finally {
            $ENV:GITHUB_API_URL = $originalApiUrl
        }
    }
}

Describe "FindLatestSuccessfulCICDRun with release artifacts" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')

        function NewCommit {
            param([string] $sha, [string[]] $parents = @())
            @{
                sha = $sha
                committer = @{ date = [DateTime]::UtcNow.ToString('o') }
                parents = @($parents | ForEach-Object { @{ sha = $_ } })
            }
        }
    }

    BeforeEach {
        $script:commits = @{
            'c2' = NewCommit 'c2' @('c1')
            'c1' = NewCommit 'c1'
        }
        $script:runs = @{}
        $script:runsWithArtifacts = @()
        Mock Write-Host -ModuleName Github-Helper {}
        Mock CheckBuildJobsInWorkflowRun -ModuleName Github-Helper { $true }
        Mock GetArtifactsFromWorkflowRun -ModuleName Github-Helper {
            if ($script:runsWithArtifacts -contains "$workflowRun" -and $mask -eq 'Apps') { @(@{ name = "P1-main-Apps-1.0.0.0" }) } else { @() }
        }
        Mock InvokeWebRequest -ModuleName Github-Helper {
            if ($uri -match '/branches/') {
                return @{ Content = (@{ commit = @{ sha = 'c2' } } | ConvertTo-Json -Depth 10) }
            }
            if ($uri -match '/git/commits/(?<sha>[^/?]+)$') {
                return @{ Content = ($script:commits[$Matches.sha] | ConvertTo-Json -Depth 10) }
            }
            if ($uri -match '/actions/runs\?.*head_sha=(?<sha>[^&]+)') {
                $runList = @()
                if ($script:runs.ContainsKey($Matches.sha)) { $runList = @($script:runs[$Matches.sha]) }
                return @{ Content = (@{ workflow_runs = $runList } | ConvertTo-Json -Depth 10) }
            }
            throw "Unexpected request: $uri"
        }
    }

    It 'returns the newest run with release artifacts regardless of the state of the run' {
        $script:runs['c2'] = @(
            @{ id = 22; head_sha = 'c2'; name = 'CI/CD'; status = 'in_progress'; conclusion = $null; created_at = '2026-10-20T10:00:00Z' },
            @{ id = 21; head_sha = 'c2'; name = 'CI/CD'; status = 'completed'; conclusion = 'failure'; created_at = '2026-10-19T10:00:00Z' }
        )
        $script:runsWithArtifacts = @('22', '21')

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7 -api_url 'https://api.github.com' -artifactProject 'P1')

        $result[0] | Should -Be 22
        $result[1] | Should -BeExactly 'c2'
        Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $uri -like '*status=completed*' }
        Should -Invoke CheckBuildJobsInWorkflowRun -ModuleName Github-Helper -Times 0 -Exactly
    }

    It 'skips runs without release artifacts and continues with the parent commit' {
        $script:runs['c2'] = @(@{ id = 22; head_sha = 'c2'; name = 'CI/CD'; status = 'completed'; conclusion = 'failure'; created_at = '2026-10-20T10:00:00Z' })
        $script:runs['c1'] = @(@{ id = 11; head_sha = 'c1'; name = 'CI/CD'; status = 'completed'; conclusion = 'failure'; created_at = '2026-10-19T10:00:00Z' })
        $script:runsWithArtifacts = @('11')

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7 -api_url 'https://api.github.com' -artifactProject 'P1')

        $result[0] | Should -Be 11
        $result[1] | Should -BeExactly 'c1'
        Should -Invoke GetArtifactsFromWorkflowRun -ModuleName Github-Helper -Times 1 -Exactly -ParameterFilter { $workflowRun -eq '22' -and $mask -eq 'PowerPlatformSolution' -and $projects -eq 'P1' -and $version -eq '*.*.*.*' }
    }

    It 'checks only the requested artifact masks' {
        $script:runs['c2'] = @(@{ id = 22; head_sha = 'c2'; name = 'CI/CD'; status = 'completed'; conclusion = 'success'; created_at = '2026-10-20T10:00:00Z' })
        $script:runsWithArtifacts = @('22')

        $result = @(FindLatestSuccessfulCICDRun -repository 'test/repo' -branch 'main' -token 'dummy' -retention 7 -api_url 'https://api.github.com' -artifactProject 'P1' -artifactMasks @('*TestApps'))

        $result[0] | Should -Be 0
        Should -Invoke GetArtifactsFromWorkflowRun -ModuleName Github-Helper -Times 0 -Exactly -ParameterFilter { $mask -eq 'Apps' }
        Should -Invoke GetArtifactsFromWorkflowRun -ModuleName Github-Helper -Times 1 -Exactly -ParameterFilter { $mask -eq '*TestApps' }
    }
}

Describe "CheckBuildJobsInWorkflowRun" {
    It 'uses the specified api_url instead of GITHUB_API_URL' {
        $originalApiUrl = $ENV:GITHUB_API_URL
        try {
            Remove-Item Env:GITHUB_API_URL -ErrorAction SilentlyContinue
            Mock Write-Host -ModuleName Github-Helper {}
            Mock InvokeWebRequest -ModuleName Github-Helper {
                if ($uri -like '*&page=1') { @{ Content = '{"jobs":[{"name":"Build Project1","conclusion":"success"}]}' } }
                else { @{ Content = '{"jobs":[]}' } }
            }

            CheckBuildJobsInWorkflowRun -headers @{} -repository 'test/repo' -workflowRunId '42' -api_url 'https://api.contoso.ghe.com' | Should -BeTrue

            Should -Invoke InvokeWebRequest -ModuleName Github-Helper -Times 2 -Exactly -ParameterFilter { $uri -like 'https://api.contoso.ghe.com/repos/test/repo/actions/runs/42/jobs?*' }
        }
        finally {
            $ENV:GITHUB_API_URL = $originalApiUrl
        }
    }
}

Describe "GetArtifactsFromWorkflowRun" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../Actions/AL-Go-Helper.ps1')
    }

    BeforeEach {
        Mock Write-Host -ModuleName Github-Helper {}
        Mock InvokeWebRequest -ModuleName Github-Helper {
            if ($uri -like '*/actions/runs/*/artifacts?*page=1') {
                return @{ Content = (@{ artifacts = @(
                    @{ id = 1; name = 'P1-main-Apps-1.0.5.0'; expired = $false },
                    @{ id = 2; name = 'P1-main-Apps-1.0.5.1'; expired = $false },
                    @{ id = 3; name = 'P1-main-BuildOutput-1.0.5.0'; expired = $false }
                ) } | ConvertTo-Json -Depth 10) }
            }
            if ($uri -like '*/actions/runs/*/artifacts?*') { return @{ Content = '{"artifacts":[]}' } }
            if ($uri -like '*/actions/runs/*') { return @{ Content = '{"head_branch":"main"}' } }
            throw "Unexpected request: $uri"
        }
    }

    It 'returns the newest version of each artifact when no version is specified' {
        $result = @(GetArtifactsFromWorkflowRun -workflowRun '501' -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -mask 'Apps' -projects 'P1')

        $result | Should -HaveCount 1
        $result[0].name | Should -BeExactly 'P1-main-Apps-1.0.5.1'
    }

    It 'returns only artifacts of the specified version' {
        $result = @(GetArtifactsFromWorkflowRun -workflowRun '502' -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -mask 'Apps' -projects 'P1' -version '1.0.5.0')

        $result | Should -HaveCount 1
        $result[0].name | Should -BeExactly 'P1-main-Apps-1.0.5.0'
    }
}

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

    It 'GetLatestRelease falls back to overall latest release for invalid version format' {
        # Mock GetReleases to return a list of releases
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '26.3.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.1.0'; prerelease = $false; draft = $false }
            )
        }

        # Test with invalid version format - should fall back to overall latest release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/abc'
        $result.tag_name | Should -Be '26.3.0'

        # Test with just ".x" - should fall back to overall latest release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/.x'
        $result.tag_name | Should -Be '26.3.0'
    }

    It 'GetLatestRelease ignores prerelease and draft releases when filtering by major version' {
        # Mock GetReleases to return a list of releases including prereleases and drafts
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '26.5.0'; prerelease = $true; draft = $false }  # prerelease - should be ignored
                [PSCustomObject]@{ tag_name = '26.4.0'; prerelease = $false; draft = $true }  # draft - should be ignored
                [PSCustomObject]@{ tag_name = '26.3.0'; prerelease = $false; draft = $false } # valid - should be selected
                [PSCustomObject]@{ tag_name = '26.2.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.1.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/26.x branch - should find the latest non-prerelease, non-draft 26.x release (26.3.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26.x'
        $result.tag_name | Should -Be '26.3.0'

        # Test releases/26 branch - should also find 26.3.0, ignoring prerelease and draft
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26'
        $result.tag_name | Should -Be '26.3.0'
    }

    It 'GetLatestRelease handles v-prefixed tags correctly' {
        # Mock GetReleases to return a list of releases with 'v' prefixed tags
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = 'v26.3.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = 'v26.2.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = 'v25.1.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = 'v25.0.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/26.x branch - should find the latest v26.x release (v26.3.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26.x'
        $result.tag_name | Should -Be 'v26.3.0'

        # Test releases/26 branch - should find the latest v26.x release (v26.3.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26'
        $result.tag_name | Should -Be 'v26.3.0'

        # Test releases/25 branch - should find the latest v25.x release (v25.1.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/25'
        $result.tag_name | Should -Be 'v25.1.0'
    }

    It 'GetLatestRelease handles mixed prefixed and non-prefixed tags' {
        # Mock GetReleases to return a mix of 'v' prefixed and non-prefixed tags
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = 'v26.3.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '26.2.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = 'v25.1.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '25.0.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/26.x branch - should find the latest 26.x release (v26.3.0, which is first)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/26.x'
        $result.tag_name | Should -Be 'v26.3.0'

        # Test releases/25.x branch - should find the latest 25.x release (v25.1.0)
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/25.x'
        $result.tag_name | Should -Be 'v25.1.0'
    }

    It 'GetLatestRelease handles alternative branch naming formats' {
        # Mock GetReleases to return a list of releases
        Mock GetReleases -ModuleName Github-Helper {
            return @(
                [PSCustomObject]@{ tag_name = '27.2.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '27.1.0'; prerelease = $false; draft = $false }
                [PSCustomObject]@{ tag_name = '26.3.0'; prerelease = $false; draft = $false }
            )
        }

        # Test releases/27x branch (without dot) - should find the latest 27.x release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/27x'
        $result.tag_name | Should -Be '27.2.0'

        # Test releases/v27 branch (with v prefix) - should find the latest 27.x release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/v27'
        $result.tag_name | Should -Be '27.2.0'

        # Test releases/v27.x branch (with v prefix and .x suffix) - should find the latest 27.x release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/v27.x'
        $result.tag_name | Should -Be '27.2.0'

        # Test releases/v26x branch (with v prefix and x suffix without dot) - should find the latest 26.x release
        $result = GetLatestRelease -token 'dummy' -api_url 'https://api.github.com' -repository 'test/repo' -ref 'releases/v26x'
        $result.tag_name | Should -Be '26.3.0'
    }

    It 'GetDependencies resolves .app files when the dependency folder path contains a glob metacharacter (])' {
        # A branch name may contain ']' (git forbids '[' but allows ']'), which ends up in the
        # downloaded dependency folder name. GetDependencies must enumerate that folder with
        # -LiteralPath; using -Path would treat ']' as a wildcard and return the folder itself
        # instead of the .app files inside it.
        $saveToPath = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
        try {
            $branch = 'bugs_Bug-638182--master]-Postserviceorder'
            $depFolder = New-Item -ItemType Directory -Path (Join-Path $saveToPath "MyProj-$branch-Apps-PR1-20260709")
            [System.IO.File]::WriteAllBytes((Join-Path $depFolder "App1.app"), [byte[]](1, 2, 3))
            [System.IO.File]::WriteAllBytes((Join-Path $depFolder "App2.app"), [byte[]](4, 5, 6))

            $probingPath = [PSCustomObject]@{
                release_status = 'thisBuild'
                buildMode      = 'Default'
                projects       = 'MyProj'
                branch         = $branch
                repo           = 'https://github.com/test/repo'
            }

            $result = @(GetDependencies -probingPathsJson $probingPath -saveToPath $saveToPath -masks @('Apps'))

            $result | Should -HaveCount 2
            $result | ForEach-Object { $_ | Should -BeLike '*.app' }
            $result | Should -Contain (Join-Path $depFolder "App1.app")
            $result | Should -Contain (Join-Path $depFolder "App2.app")
        }
        finally {
            Remove-Item -Path $saveToPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
