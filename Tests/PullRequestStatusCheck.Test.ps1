[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'optionalJobName', Justification = 'Used by Pester test and mock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'requiredJobName', Justification = 'Used by Pester test and mock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'jobsJson', Justification = 'Used by Pester mocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Patterns', Justification = 'Used in Pester assertion scriptblocks.')]
param()

Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "PullRequestStatusCheck Action Tests" {
    BeforeAll {
        $actionName = "PullRequestStatusCheck"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
        # Import Github-Helper so Invoke-CommandWithRetry is available and its Start-Sleep can be mocked.
        Import-Module (Join-Path $scriptRoot '..\Github-Helper.psm1' -Resolve) -DisableNameChecking
        $ENV:GITHUB_REPOSITORY = "organization/repository"
        $ENV:GITHUB_RUN_ID = "123456"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalServerUrl', Justification = 'False positive.')]
        $originalServerUrl = $ENV:GITHUB_SERVER_URL
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalGhHost', Justification = 'False positive.')]
        $originalGhHost = $ENV:GH_HOST
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalGithubOutput', Justification = 'Used in AfterAll.')]
        $originalGithubOutput = $ENV:GITHUB_OUTPUT
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'originalSettings', Justification = 'Used in AfterAll.')]
        $originalSettings = $ENV:Settings
        $ENV:GITHUB_SERVER_URL = "https://github.com"
    }

    BeforeEach {
        $ENV:GITHUB_OUTPUT = Join-Path $TestDrive 'github_output.txt'
        Set-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Value $null
        $ENV:Settings = '{"optionalPatternsForPrValidation":[]}'
    }

    AfterAll {
        $ENV:GITHUB_SERVER_URL = $originalServerUrl
        $ENV:GH_HOST = $originalGhHost
        $ENV:GITHUB_OUTPUT = $originalGithubOutput
        $ENV:Settings = $originalSettings
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "failedOptionalJobs" = "JSON array of failed optional build job names"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    It 'should fail if there is a job that fails' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 0; '{"total_count":3,"jobs":[{ "name": "job1", "conclusion":  "success" },{ "name": "job2", "conclusion":  "skipped" },{ "name": "job3", "conclusion":  "failure" }]}' }
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage 'PR Build failed. Failing jobs: job3'
    }

    It 'should detect failing jobs across multiple pages (gh --slurp returns an array)' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 0; '[{"total_count":4,"jobs":[{ "name": "job1", "conclusion": "success" },{ "name": "job2", "conclusion": "success" }]},{"total_count":4,"jobs":[{ "name": "job3", "conclusion": "success" },{ "name": "job4", "conclusion": "failure" }]}]' }
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage 'PR Build failed. Failing jobs: job4'
    }

    It 'should complete if there are no failing jobs' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 0; '{"total_count":3,"jobs":[{ "name": "job1", "conclusion":  "success" },{ "name": "job2", "conclusion":  "skipped" },{ "name": "job3", "conclusion":  "success" }]}' }
        Mock Write-Host {}
        & $scriptPath
        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter { $Object -eq "PR Build succeeded" }
        (Get-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Raw).Trim() | Should -Be 'failedOptionalJobs=[]'
        $ENV:GH_HOST | Should -Be 'github.com'
    }

    It 'should retry when the jobs API call fails and then give up' {
        Mock -CommandName gh -MockWith { $global:LASTEXITCODE = 1 }
        Mock -CommandName Start-Sleep -ModuleName Github-Helper -MockWith {}
        {
            & $scriptPath
        } | Should -Throw -ExpectedMessage '*Failed to get jobs for run*'
        Assert-MockCalled gh -Exactly 5 -Scope It
    }

    Context 'Optional build failures' {
        BeforeAll {
            $optionalJobName = 'Build Alpha (NextMinor) / Alpha (NextMinor)'
            $requiredJobName = 'Build Beta (Default) / Beta (Default)'
        }

        BeforeEach {
            $jobsJson = ConvertTo-Json -InputObject @{ jobs = @(
                @{ name = $optionalJobName; conclusion = 'failure' }
                @{ name = $requiredJobName; conclusion = 'success' }
            ) } -Depth 10
            Mock gh { $global:LASTEXITCODE = 0; $jobsJson }
            Mock OutputWarning {}
            Mock Write-Host {}
            Mock Start-Sleep -ModuleName Github-Helper {}
        }

        It 'Allows an optional failure using <Patterns>' -TestCases @(
            @{ Patterns = '["Build Alpha (NextMinor) / Alpha (NextMinor)"]' }
            @{ Patterns = '["*NextMinor*"]' }
            @{ Patterns = '["*nextminor*"]' }
            @{ Patterns = '["Build Alph? (*) / *"]' }
            @{ Patterns = '["Build [AB]*"]' }
            @{ Patterns = '["no match","*NextMinor*"]' }
        ) {
            param($Patterns)
            $ENV:Settings = "{`"optionalPatternsForPrValidation`":$Patterns}"
            & $scriptPath
            Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { $message -eq "Optional PR build job failed (non-blocking): $optionalJobName" }
            Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter { $Object -eq 'PR Build succeeded' }
            $outputJson = (Get-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Raw).Trim() -replace '^failedOptionalJobs=', ''
            $outputJson | Should -Be (ConvertTo-Json -InputObject @($optionalJobName) -Compress)
        }

        It 'Preserves failures with <Patterns>' -TestCases @(
            @{ Patterns = '[]' }
            @{ Patterns = '["no match"]' }
        ) {
            param($Patterns)
            $ENV:Settings = "{`"optionalPatternsForPrValidation`":$Patterns}"
            { & $scriptPath } |
                Should -Throw -ExpectedMessage "PR Build failed. Failing jobs: $optionalJobName"
            (Get-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Raw).Trim() | Should -Be 'failedOptionalJobs=[]'
        }

        It 'Warns about optional failures and only reports required failures across pages' {
            $jobsJson = '[{"jobs":[{"name":"Build Alpha (NextMinor) / Alpha (NextMinor)","conclusion":"failure"}]},{"jobs":[{"name":"Build Beta (Default) / Beta (Default)","conclusion":"failure"}]}]'
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*NextMinor*"]}'
            { & $scriptPath } |
                Should -Throw -ExpectedMessage "PR Build failed. Failing jobs: $requiredJobName"
            Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { $message -like 'Optional PR build job failed*' }
            $outputJson = (Get-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Raw).Trim() -replace '^failedOptionalJobs=', ''
            $outputJson | Should -Be (ConvertTo-Json -InputObject @($optionalJobName) -Compress)
        }

        It 'Outputs only failed optional build names across pages and escapes JSON characters' {
            $escapedJobName = 'Build "Custom" (NextMinor) / Custom\Path (NextMinor)'
            $jobsJson = ConvertTo-Json -InputObject @(
                @{ jobs = @(
                    @{ name = $optionalJobName; conclusion = 'failure' }
                    @{ name = $optionalJobName; conclusion = 'success' }
                    @{ name = 'Initialization'; conclusion = 'skipped' }
                ) }
                @{ jobs = @(
                    @{ name = $escapedJobName; conclusion = 'failure' }
                    @{ name = $optionalJobName; conclusion = 'cancelled' }
                ) }
            ) -Depth 10
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*"]}'
            & $scriptPath
            $outputJson = (Get-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Raw).Trim() -replace '^failedOptionalJobs=', ''
            $outputJson | Should -Be (ConvertTo-Json -InputObject @($optionalJobName, $escapedJobName) -Compress)
        }

        It 'Keeps non-build jobs required even with a broad wildcard: <Name>' -TestCases @(
            @{ Name = 'Initialization' }
            @{ Name = 'PregateCheck' }
            @{ Name = 'Code Analysis Processing' }
            @{ Name = 'Build Custom (NextMinor)' }
            @{ Name = 'Custom (NextMinor) / Custom (NextMinor)' }
            @{ Name = 'Build Custom / Custom' }
            @{ Name = 'Build Custom (NextMinor) / Setup' }
        ) {
            param($Name)
            $jobsJson = ConvertTo-Json -InputObject @{ jobs = @(@{ name = $Name; conclusion = 'failure' }) } -Depth 10
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*"]}'
            { & $scriptPath } |
                Should -Throw -ExpectedMessage "PR Build failed. Failing jobs: $Name"
        }

        It 'Keeps infrastructure failures blocking alongside optional build failures' {
            $jobsJson = ConvertTo-Json -InputObject @{ jobs = @(
                @{ name = $optionalJobName; conclusion = 'failure' }
                @{ name = 'Initialization'; conclusion = 'failure' }
            ) } -Depth 10
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*"]}'
            { & $scriptPath } |
                Should -Throw -ExpectedMessage 'PR Build failed. Failing jobs: Initialization'
            Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { $message -like 'Optional PR build job failed*' }
        }

        It 'Allows matching build names without build metadata: <Name>' -TestCases @(
            @{ Name = 'Build Custom (NextMinor) / Custom (NextMinor)' }
            @{ Name = 'Build Beta (Default) / Beta (Default)' }
            @{ Name = 'build alpha (nextminor) / alpha (nextminor)' }
            @{ Name = 'Build Al* (NextMinor) / Al* (NextMinor)' }
        ) {
            param($Name)
            $jobsJson = ConvertTo-Json -InputObject @{ jobs = @(@{ name = $Name; conclusion = 'failure' }) } -Depth 10
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*"]}'
            & $scriptPath
            Assert-MockCalled OutputWarning -Exactly 1 -ParameterFilter { $message -like 'Optional PR build job failed*' }
        }

        It 'Allows optional failures with duplicate API names and <Conclusion> conclusions' -TestCases @(
            @{ Conclusion = 'success'; Warnings = 1 }
            @{ Conclusion = 'failure'; Warnings = 2 }
        ) {
            param($Conclusion, $Warnings)
            $jobsJson = ConvertTo-Json -InputObject @{ jobs = @(
                @{ name = $optionalJobName; conclusion = 'failure' }
                @{ name = $optionalJobName; conclusion = $Conclusion }
            ) } -Depth 10
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*"]}'
            & $scriptPath
            Assert-MockCalled OutputWarning -Exactly $Warnings -ParameterFilter { $message -eq "Optional PR build job failed (non-blocking): $optionalJobName" }
            Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter { $Object -eq 'PR Build succeeded' }
        }

        It 'Preserves non-failure conclusions: <Conclusion>' -TestCases @(
            @{ Conclusion = 'skipped' }
            @{ Conclusion = 'cancelled' }
            @{ Conclusion = 'timed_out' }
            @{ Conclusion = 'success' }
        ) {
            param($Conclusion)
            $jobsJson = ConvertTo-Json -InputObject @{ jobs = @(@{ name = 'Initialization'; conclusion = $Conclusion }) } -Depth 10
            $ENV:Settings = '{"optionalPatternsForPrValidation":["*"]}'
            & $scriptPath
            Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter { $Object -eq 'PR Build succeeded' }
        }

        It 'Rejects malformed input: <Patterns>' -TestCases @(
            @{ Patterns = '{}' }
            @{ Patterns = 'null' }
            @{ Patterns = '[1]' }
            @{ Patterns = '[null]' }
            @{ Patterns = '[[]]' }
            @{ Patterns = '["["]' }
            @{ Patterns = '[' }
        ) {
            param($Patterns)
            $ENV:Settings = "{`"optionalPatternsForPrValidation`":$Patterns}"
            { & $scriptPath } | Should -Throw
            Assert-MockCalled gh -Exactly 0
        }
    }
}
