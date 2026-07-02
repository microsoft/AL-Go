[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '../Actions/.Modules/CheckForWarningsUtils.psm1' -Resolve) -DisableNameChecking -Force

Describe 'CheckForWarningsUtils.psm1 Tests' {
    BeforeAll {
        # The module functions call Trace-Information (telemetry). Provide a global no-op stub so the
        # tests don't depend on telemetry configuration or make network calls.
        function global:Trace-Information { param([string] $Message) }

        $script:warningLine1 = '::warning file=App/MyCodeunit.al,line=10,col=5::AA0001 The variable is never used.'
        $script:warningLine2 = '::warning file=App/MyPage.al,line=42,col=9::AL0603 The property has been deprecated.'
    }

    Context 'Get-Warnings' {
        It 'Parses warning lines into structured objects' {
            InModuleScope CheckForWarningsUtils -Parameters @{ warningLine = $warningLine1 } {
                param($warningLine)
                $file = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $file -Value @($warningLine, 'Some unrelated build output line') -Encoding UTF8
                $warnings = @(Get-Warnings -BuildFile $file)
                $warnings.Count | Should -Be 1
                $warnings[0].Id | Should -Be 'AA0001'
                $warnings[0].File | Should -Be 'App/MyCodeunit.al'
                $warnings[0].Line | Should -Be '10'
                $warnings[0].Col | Should -Be '5'
            }
        }

        It 'Returns nothing for a build log with no warnings' {
            InModuleScope CheckForWarningsUtils {
                $file = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $file -Value @('Compiling...', 'Done.') -Encoding UTF8
                @(Get-Warnings -BuildFile $file).Count | Should -Be 0
            }
        }

        It 'Returns nothing when the build file does not exist' {
            InModuleScope CheckForWarningsUtils {
                @(Get-Warnings -BuildFile (Join-Path $TestDrive 'does-not-exist.txt')).Count | Should -Be 0
            }
        }
    }

    Context 'Compare-Files' {
        It 'Does not throw when the PR introduces no new warnings' {
            InModuleScope CheckForWarningsUtils -Parameters @{ warningLine1 = $warningLine1 } {
                param($warningLine1)
                $reference = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                $pr = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $reference -Value @($warningLine1) -Encoding UTF8
                Set-Content -Path $pr -Value @($warningLine1) -Encoding UTF8
                { Compare-Files -referenceBuild $reference -prBuild $pr } | Should -Not -Throw
            }
        }

        It 'Throws when the PR introduces a new warning' {
            InModuleScope CheckForWarningsUtils -Parameters @{ warningLine1 = $warningLine1; warningLine2 = $warningLine2 } {
                param($warningLine1, $warningLine2)
                $reference = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                $pr = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $reference -Value @($warningLine1) -Encoding UTF8
                Set-Content -Path $pr -Value @($warningLine1, $warningLine2) -Encoding UTF8
                { Compare-Files -referenceBuild $reference -prBuild $pr } | Should -Throw '*New warnings were introduced*'
            }
        }

        It 'Does not throw when a pre-existing warning is removed' {
            InModuleScope CheckForWarningsUtils -Parameters @{ warningLine1 = $warningLine1; warningLine2 = $warningLine2 } {
                param($warningLine1, $warningLine2)
                $reference = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                $pr = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $reference -Value @($warningLine1, $warningLine2) -Encoding UTF8
                Set-Content -Path $pr -Value @($warningLine1) -Encoding UTF8
                { Compare-Files -referenceBuild $reference -prBuild $pr } | Should -Not -Throw
            }
        }
    }

    Context 'Test-ForNewWarnings guards' {
        It 'Returns without checking when the build is not a pull request' {
            $savedBaseRef = $ENV:GITHUB_BASE_REF
            try {
                $ENV:GITHUB_BASE_REF = ''
                { Test-ForNewWarnings -token 'token' -project 'P1' -settings @{ failOn = 'newWarning' } -buildMode 'Default' -prBuildOutputFile 'BuildOutput.txt' -baselineWorkflowRunId '123' } | Should -Not -Throw
            }
            finally {
                $ENV:GITHUB_BASE_REF = $savedBaseRef
            }
        }

        It 'Returns without checking when failOn is not newWarning' {
            $savedBaseRef = $ENV:GITHUB_BASE_REF
            try {
                $ENV:GITHUB_BASE_REF = 'main'
                { Test-ForNewWarnings -token 'token' -project 'P1' -settings @{ failOn = 'error' } -buildMode 'Default' -prBuildOutputFile 'BuildOutput.txt' -baselineWorkflowRunId '123' } | Should -Not -Throw
            }
            finally {
                $ENV:GITHUB_BASE_REF = $savedBaseRef
            }
        }
    }
}
