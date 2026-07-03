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
        # Raw AL compiler format emitted by workspace compilation into BuildOutput.txt
        $script:alcWarningLine1 = "Codeunits\MyCodeunit.al(10,5): warning AA0001: The variable is never used."
        $script:alcWarningLine2 = "Pages\MyPage.al(42,9): warning AL0603: The property has been deprecated."
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
                $warnings[0].Description | Should -Be 'The variable is never used.'
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

        It 'Parses raw AL compiler (workspace compilation) warning format' {
            InModuleScope CheckForWarningsUtils -Parameters @{ alcLine = $alcWarningLine1 } {
                param($alcLine)
                $file = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $file -Value @($alcLine, 'Compilation completed successfully.') -Encoding UTF8
                $warnings = @(Get-Warnings -BuildFile $file)
                $warnings.Count | Should -Be 1
                $warnings[0].Id | Should -Be 'AA0001'
                # File separators are normalized to forward slashes regardless of source format.
                $warnings[0].File | Should -Be 'Codeunits/MyCodeunit.al'
                $warnings[0].Description | Should -Be 'The variable is never used.'
                $warnings[0].Line | Should -Be '10'
                $warnings[0].Col | Should -Be '5'
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

        It 'Throws when the PR introduces a new warning in raw AL compiler (workspace) format' {
            InModuleScope CheckForWarningsUtils -Parameters @{ alcWarningLine1 = $alcWarningLine1; alcWarningLine2 = $alcWarningLine2 } {
                param($alcWarningLine1, $alcWarningLine2)
                $reference = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                $pr = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $reference -Value @($alcWarningLine1) -Encoding UTF8
                Set-Content -Path $pr -Value @($alcWarningLine1, $alcWarningLine2) -Encoding UTF8
                { Compare-Files -referenceBuild $reference -prBuild $pr } | Should -Throw '*New warnings were introduced*'
            }
        }

        It 'Does not throw when only an embedded build version in the description differs' {
            InModuleScope CheckForWarningsUtils {
                # Same AL0523 warning, but the referenced base app version differs between builds
                # (the build/revision numbers come from the workflow run number).
                $refLine = "Bank\PostedDepositLine.Table.al(10,5): warning AL0523: The Table 'Posted Deposit Line' already defines a method called 'ShowDimensions' with the same parameter types in 'Base Application by Microsoft (29.0.2147483647.75423)'. This warning will become an error in a future release."
                $prLine = "Bank\PostedDepositLine.Table.al(10,5): warning AL0523: The Table 'Posted Deposit Line' already defines a method called 'ShowDimensions' with the same parameter types in 'Base Application by Microsoft (29.0.2147483647.75450)'. This warning will become an error in a future release."
                $reference = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                $pr = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $reference -Value @($refLine) -Encoding UTF8
                Set-Content -Path $pr -Value @($prLine) -Encoding UTF8
                { Compare-Files -referenceBuild $reference -prBuild $pr } | Should -Not -Throw
            }
        }

        It 'Does not throw when the same warning appears in different compilation formats' {
            InModuleScope CheckForWarningsUtils {
                # A project that switches between container and workspace compilation will have a baseline
                # in one format and a PR build in the other. The same warning must match across formats,
                # including the path separator difference (forward slash vs backslash).
                $refLine = '::warning file=Bank/MyCodeunit.al,line=10,col=5::AA0001 The variable is never used.'
                $prLine = "Bank\MyCodeunit.al(10,5): warning AA0001: The variable is never used."
                $reference = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                $pr = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
                Set-Content -Path $reference -Value @($refLine) -Encoding UTF8
                Set-Content -Path $pr -Value @($prLine) -Encoding UTF8
                { Compare-Files -referenceBuild $reference -prBuild $pr } | Should -Not -Throw
            }
        }
    }

    Context 'Get-NormalizedWarningDescription' {
        It 'Replaces a four-part version number with a placeholder' {
            InModuleScope CheckForWarningsUtils {
                Get-NormalizedWarningDescription -Description "references 'App (1.2.3.4)'" | Should -Be "references 'App ({version})'"
            }
        }

        It 'Replaces multiple four-part version numbers in one description' {
            InModuleScope CheckForWarningsUtils {
                Get-NormalizedWarningDescription -Description 'from (1.0.0.1) to (2.0.0.2)' | Should -Be 'from ({version}) to ({version})'
            }
        }

        It 'Leaves a three-part version untouched' {
            InModuleScope CheckForWarningsUtils {
                Get-NormalizedWarningDescription -Description 'version 1.2.3 is fine' | Should -Be 'version 1.2.3 is fine'
            }
        }

        It 'Leaves a description without a version unchanged' {
            InModuleScope CheckForWarningsUtils {
                Get-NormalizedWarningDescription -Description 'The variable is never used.' | Should -Be 'The variable is never used.'
            }
        }

        It 'Returns an empty string for empty input' {
            InModuleScope CheckForWarningsUtils {
                Get-NormalizedWarningDescription -Description '' | Should -Be ''
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
