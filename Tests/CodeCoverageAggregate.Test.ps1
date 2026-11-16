[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in Pester test scopes')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\AnalyzeCodeCoverage.psm1" -Resolve) `
    -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageAggregate.psm1" -Resolve) `
    -Force -DisableNameChecking

Describe "Code coverage aggregate" {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageAggregateFormat.psm1" -Resolve) `
            -Force -DisableNameChecking

        function New-AggregateRepository {
            Param([string] $name)

            $repositoryRoot = Join-Path $TestDrive $name
            $appRoot = Join-Path $repositoryRoot "App"
            New-Item -Path $appRoot -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $appRoot "File.al") `
                -Value "codeunit 50100 Example { }" -Encoding UTF8
            return $repositoryRoot
        }

        function New-AggregateStatus {
            Param(
                [string] $coverageRoot,
                [object[]] $runs
            )

            $status = [ordered]@{
                project = "."
                projectName = "Project"
                buildMode = "Default"
                formats = @("bc-json")
                sourceRoots = @("App")
                sourceRootDetails = @([ordered]@{
                        path = "App"
                        kind = "app"
                        appId = "11111111-1111-1111-1111-111111111111"
                        appName = "Regular App"
                    })
                runs = @($runs)
            }
            $status | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8
            return $status
        }

        function Write-AggregateRawReport {
            Param(
                [string] $path,
                [int] $hitCount,
                [bool] $complete = $true,
                [string[]] $diagnostics = @()
            )

            New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
            [ordered]@{
                schemaVersion = "1.0"
                coverageMode = "line"
                complete = $complete
                diagnostics = @($diagnostics)
                sources = @("File.al")
                tests = @()
                procedureEdges = @()
                methods = @([ordered]@{
                        objectType = 5
                        objectId = 50100
                        methodId = 1
                        name = "Run"
                        startLine = 10
                        endLine = 12
                        sourcePath = "File.al"
                    })
                lines = @([ordered]@{
                        objectType = 5
                        objectId = 50100
                        lineNumber = 11
                        lineType = 3
                        methodId = 1
                        hitCount = $hitCount
                        status = if ($hitCount -gt 0) { 1 } else { 0 }
                        sourcePath = "File.al"
                    })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
        }

        function Get-AggregateMetadata {
            Param([object] $status)

            return @{
                Mode = "line"
                SourceRoots = @($status.sourceRoots)
                SourceRootDetails = @($status.sourceRootDetails)
            }
        }

        function Convert-RawArtifactToAggregate {
            Param(
                [string] $artifactRoot,
                [string] $repositoryRoot
            )

            $coverageRoot = Join-Path $artifactRoot "CodeCoverage"
            $statusPath = Join-Path $coverageRoot "coverage-status.json"
            $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $metadata = Get-AggregateMetadata -status $status
            $publishedPath = Join-Path $coverageRoot "coverage-aggregate.bin.gz"
            $worker = Start-CodeCoverageAggregateWorker `
                -readerModulePath (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
                -repositoryRoot $repositoryRoot -metadata $metadata `
                -temporaryPath "$publishedPath.tmp" -publishedPath $publishedPath
            $sequence = 0
            foreach ($run in @($status.runs)) {
                if ("$($run.state)" -in @("complete", "incomplete")) {
                    Add-CodeCoverageAggregateWorkItem -worker $worker -descriptor @{
                        Sequence = $sequence
                        AppId = "$($run.appId)"
                        AppName = "$($run.appName)"
                        State = "$($run.state)"
                        Complete = "$($run.state)" -eq "complete"
                        ReportPath = Join-Path (Join-Path $coverageRoot (
                                Split-Path "$($run.outputDirectory)" -Leaf)) "coverage.bc.json"
                    }
                }

                $sequence++
            }
            $aggregate = Complete-CodeCoverageAggregateWorker -worker $worker
            foreach ($assessment in @($aggregate.RunAssessments)) {
                $run = $status.runs[[int]$assessment.Sequence]
                $run | Add-Member -NotePropertyName lineReasons `
                    -NotePropertyValue @($assessment.LineReasons)
                $run | Add-Member -NotePropertyName notices `
                    -NotePropertyValue @($assessment.Notices)
                $run | Add-Member -NotePropertyName lineGlobalUnsafe `
                    -NotePropertyValue ([bool]$assessment.LineGlobalUnsafe)
                $run | Add-Member -NotePropertyName lineAffectedSources `
                    -NotePropertyValue @($assessment.LineAffectedSources)
                $run | Add-Member -NotePropertyName excludedLineFacts `
                    -NotePropertyValue ([int]$assessment.ExcludedLineFacts)
            }
            $status | Add-Member -NotePropertyName aggregate `
                -NotePropertyValue "coverage-aggregate.bin.gz"
            $status | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $statusPath -Encoding UTF8
            foreach ($rawReport in @(Get-ChildItem -LiteralPath $coverageRoot `
                    -Filter "coverage.bc.json" -File -Recurse)) {
                Remove-Item -LiteralPath $rawReport.FullName -Force
            }
        }

        function New-AggregateOnlyProjectArtifact {
            Param(
                [string] $root,
                [string] $artifactName,
                [string] $project,
                [string] $appId,
                [bool] $covered
            )

            $coverageRoot = Join-Path (Join-Path $root $artifactName) "CodeCoverage"
            New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
            $details = @([ordered]@{
                    path = "Shared"; kind = "app"; appId = $appId; appName = "$project app"
                })
            $aggregatePath = Join-Path $coverageRoot "coverage-aggregate.bin.gz"
            Write-CodeCoverageAggregateFile -path $aggregatePath -lines @{
                "shared" = @{ "shared/file.al|5|1|10" = $covered }
            }
            [ordered]@{
                project = $project
                projectName = $project
                buildMode = "Default"
                formats = @("bc-json")
                sourceRoots = @("Shared")
                sourceRootDetails = $details
                runs = @([ordered]@{
                        appId = "$project-run"; appName = "$project tests"
                        outputDirectory = "CodeCoverage/$project-run"; state = "complete"
                        lineReasons = @(); notices = @(); lineGlobalUnsafe = $false
                        lineAffectedSources = @(); excludedLineFacts = 0
                    })
                aggregate = "coverage-aggregate.bin.gz"
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8
        }
    }

    It "produces an aggregate with duplicate OR semantics" {
        $repositoryRoot = New-AggregateRepository -name "Equivalent"
        $coverageRoot = Join-Path $repositoryRoot ".buildartifacts\CodeCoverage"
        New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
        $runs = @(
            [ordered]@{ appId = "run-a"; appName = "Run A"; outputDirectory = "CodeCoverage/run-a"; state = "complete" },
            [ordered]@{ appId = "run-b"; appName = "Run B"; outputDirectory = "CodeCoverage/run-b"; state = "complete" }
        )
        $status = New-AggregateStatus -coverageRoot $coverageRoot -runs $runs
        $reportA = Join-Path $coverageRoot "run-a\coverage.bc.json"
        $reportB = Join-Path $coverageRoot "run-b\coverage.bc.json"
        Write-AggregateRawReport -path $reportA -hitCount 0
        Write-AggregateRawReport -path $reportB -hitCount 1

        $metadata = Get-AggregateMetadata -status $status
        $publishedPath = Join-Path $coverageRoot "coverage-aggregate.bin.gz"
        $worker = Start-CodeCoverageAggregateWorker `
            -readerModulePath (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
            -repositoryRoot $repositoryRoot -metadata $metadata `
            -temporaryPath "$publishedPath.tmp" -publishedPath $publishedPath
        Add-CodeCoverageAggregateWorkItem -worker $worker -descriptor @{
            Sequence = 0; AppId = "run-a"; AppName = "Run A"; State = "complete"
            Complete = $true; ReportPath = $reportA
        }
        Add-CodeCoverageAggregateWorkItem -worker $worker -descriptor @{
            Sequence = 1; AppId = "run-b"; AppName = "Run B"; State = "complete"
            Complete = $true; ReportPath = $reportB
        }
        Test-Path -LiteralPath $publishedPath | Should -BeFalse
        $aggregate = Complete-CodeCoverageAggregateWorker -worker $worker
        foreach ($assessment in @($aggregate.RunAssessments)) {
            $run = $status.runs[[int]$assessment.Sequence]
            $run["lineReasons"] = @($assessment.LineReasons)
            $run["notices"] = @($assessment.Notices)
            $run["lineGlobalUnsafe"] = [bool]$assessment.LineGlobalUnsafe
            $run["lineAffectedSources"] = @($assessment.LineAffectedSources)
            $run["excludedLineFacts"] = [int]$assessment.ExcludedLineFacts
        }
        $status["aggregate"] = "coverage-aggregate.bin.gz"
        $status | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8
        Remove-Item -LiteralPath $reportA, $reportB -Force

        $aggregateModel = Get-ProjectCoverageModel `
            -CoveragePath (Split-Path $coverageRoot -Parent) -RepositoryRoot $repositoryRoot

        $aggregateModel.LineComplete | Should -BeTrue
        $aggregateMetrics = Get-CoverageMetrics $aggregateModel.Lines
        $aggregateMetrics.Total | Should -Be 1
        $aggregateMetrics.Covered | Should -Be 1
        $aggregateMetrics.Uncovered | Should -Be 0
        $aggregateMetrics.Percentage | Should -Be 100
        New-ProjectCoverageSummary $aggregateModel | Should -Match "100\.0%"
        $aggregate.LineCount | Should -Be 1
        Test-Path -LiteralPath $reportA | Should -BeFalse
        Test-Path -LiteralPath $reportB | Should -BeFalse
    }

    It "retains raw input and publishes nothing when the worker rejects corrupt JSON" {
        $repositoryRoot = New-AggregateRepository -name "Corrupt"
        $coverageRoot = Join-Path $repositoryRoot ".buildartifacts\CodeCoverage"
        New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
        $status = New-AggregateStatus -coverageRoot $coverageRoot -runs @(
            [ordered]@{ appId = "run-a"; appName = "Run A"; outputDirectory = "CodeCoverage/run-a"; state = "complete" }
        )
        $reportPath = Join-Path $coverageRoot "run-a\coverage.bc.json"
        New-Item -Path (Split-Path $reportPath -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $reportPath -Value '{"schemaVersion":' -Encoding UTF8
        $publishedPath = Join-Path $coverageRoot "coverage-aggregate.bin.gz"
        $worker = Start-CodeCoverageAggregateWorker `
            -readerModulePath (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageReportReader.psm1" -Resolve) `
            -repositoryRoot $repositoryRoot -metadata (Get-AggregateMetadata -status $status) `
            -temporaryPath "$publishedPath.tmp" -publishedPath $publishedPath
        Add-CodeCoverageAggregateWorkItem -worker $worker -descriptor @{
            Sequence = 0; AppId = "run-a"; AppName = "Run A"; State = "complete"
            Complete = $true; ReportPath = $reportPath
        }

        { Complete-CodeCoverageAggregateWorker -worker $worker } | Should -Throw
        Test-Path -LiteralPath $reportPath | Should -BeTrue
        Test-Path -LiteralPath $publishedPath | Should -BeFalse
        Test-Path -LiteralPath "$publishedPath.tmp" | Should -BeFalse
    }

    It "preserves incomplete diagnostic scoping and project Markdown" {
        $fixtureRoot = Join-Path $PSScriptRoot "TestArtifacts\CodeCoverage\ScopedIncomplete"
        $aggregateArtifact = Join-Path $TestDrive "ScopedAggregate"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $aggregateArtifact -Recurse
        $repositoryRoot = Join-Path $fixtureRoot "Repository"

        Convert-RawArtifactToAggregate -artifactRoot $aggregateArtifact `
            -repositoryRoot $repositoryRoot
        $aggregateModel = Get-ProjectCoverageModel -CoveragePath $aggregateArtifact `
            -RepositoryRoot $repositoryRoot

        $aggregateModel.LineComplete | Should -BeTrue
        $aggregateModel.Reasons | Should -BeNullOrEmpty
        $aggregateModel.LineReasons | Should -BeNullOrEmpty
        $aggregateModel.Notices.Count | Should -Be 6
        $aggregateModel.ExcludedLineFacts | Should -Be 2
        New-ProjectCoverageSummary $aggregateModel | Should -Match "50\.0%"
        @(Get-ChildItem -LiteralPath $aggregateArtifact -Filter "coverage.bc.json" -File -Recurse).Count |
            Should -Be 0
    }

    It "rejects trailing decompressed data" {
        $path = Join-Path $TestDrive "trailing.bin.gz"
        $fileStream = [System.IO.File]::Create($path)
        $gzipStream = [System.IO.Compression.GZipStream]::new(
            $fileStream, [System.IO.Compression.CompressionLevel]::Fastest, $false)
        try {
            $writer = [System.IO.BinaryWriter]::new($gzipStream)
            $writer.Write([System.Text.Encoding]::ASCII.GetBytes("ALGOCOV1"))
            $writer.Write([long]0)
            $writer.Write([byte]1)
            $writer.Dispose()
        }
        finally {
            if ($gzipStream) { $gzipStream.Dispose() }
            if ($fileStream) { $fileStream.Dispose() }
        }

        $result = Read-CodeCoverageAggregate -path $path

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Match "corrupt"
    }

    It "rejects truncated compressed data" {
        $path = Join-Path $TestDrive "truncated.bin.gz"
        Write-CodeCoverageAggregateFile -path $path -lines @{
            "app" = @{ "app/file.al|5|1|10" = $true }
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        [System.IO.File]::WriteAllBytes($path, $bytes[0..($bytes.Length - 5)])

        $result = Read-CodeCoverageAggregate -path $path

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Match "corrupt"
    }

    It "does not fall back to raw reports when a published aggregate is corrupt" {
        $repositoryRoot = New-AggregateRepository -name "PublishedCorrupt"
        $coverageRoot = Join-Path $repositoryRoot ".buildartifacts\CodeCoverage"
        New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
        $status = New-AggregateStatus -coverageRoot $coverageRoot -runs @(
            [ordered]@{ appId = "run-a"; appName = "Run A"; outputDirectory = "CodeCoverage/run-a"; state = "complete" }
        )
        Write-AggregateRawReport -path (
            Join-Path $coverageRoot "run-a\coverage.bc.json"
        ) -hitCount 1
        $aggregatePath = Join-Path $coverageRoot "coverage-aggregate.bin.gz"
        Set-Content -LiteralPath $aggregatePath -Value "not gzip" -Encoding UTF8
        $status.runs[0]["lineReasons"] = @()
        $status.runs[0]["notices"] = @()
        $status.runs[0]["lineGlobalUnsafe"] = $false
        $status.runs[0]["lineAffectedSources"] = @()
        $status.runs[0]["excludedLineFacts"] = 0
        $status["aggregate"] = "coverage-aggregate.bin.gz"
        $status | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8

        $model = Get-ProjectCoverageModel `
            -CoveragePath (Split-Path $coverageRoot -Parent) -RepositoryRoot $repositoryRoot

        $model.LineComplete | Should -BeFalse
        $model.Reasons -join " " | Should -Match "published code coverage aggregate is invalid"
    }

    It "requires run assessments from status when an aggregate is published" {
        $repositoryRoot = New-AggregateRepository -name "MissingAssessment"
        $coverageRoot = Join-Path $repositoryRoot ".buildartifacts\CodeCoverage"
        New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
        $status = New-AggregateStatus -coverageRoot $coverageRoot -runs @(
            [ordered]@{
                appId = "run-a"; appName = "Run A"
                outputDirectory = "CodeCoverage/run-a"; state = "complete"
            }
        )
        Write-CodeCoverageAggregateFile `
            -path (Join-Path $coverageRoot "coverage-aggregate.bin.gz") `
            -lines @{ "app" = @{ "app/file.al|5|50100|11" = $true } }
        $status["aggregate"] = "coverage-aggregate.bin.gz"
        $status | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8

        $model = Get-ProjectCoverageModel `
            -CoveragePath (Split-Path $coverageRoot -Parent) -RepositoryRoot $repositoryRoot

        $model.LineComplete | Should -BeFalse
        $model.Reasons -join " " | Should -Match "missing the run assessment"
    }

    It "rejects aggregate references other than the fixed filename" {
        $repositoryRoot = New-AggregateRepository -name "InvalidReference"
        $coverageRoot = Join-Path $repositoryRoot ".buildartifacts\CodeCoverage"
        New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
        $status = New-AggregateStatus -coverageRoot $coverageRoot -runs @(
            [ordered]@{
                appId = "run-a"; appName = "Run A"
                outputDirectory = "CodeCoverage/run-a"; state = "complete"
                lineReasons = @(); notices = @(); lineGlobalUnsafe = $false
                lineAffectedSources = @(); excludedLineFacts = 0
            }
        )
        $status["aggregate"] = "../coverage-aggregate.bin.gz"
        $status | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8

        $model = Get-ProjectCoverageModel `
            -CoveragePath (Split-Path $coverageRoot -Parent) -RepositoryRoot $repositoryRoot

        $model.LineComplete | Should -BeFalse
        $model.Reasons -join " " | Should -Match "aggregate reference is invalid"
    }

    It "reads the versioned aggregate on Windows PowerShell compatible APIs" {
        $path = Join-Path $TestDrive "portable.bin.gz"
        $lines = @{ "app" = @{ "app/file.al|5|1|10" = $true } }
        Write-CodeCoverageAggregateFile -path $path -lines $lines

        $result = Read-CodeCoverageAggregate -path $path

        $result.Valid | Should -BeTrue
        $result.LineCount | Should -Be 1
        $result.ApplicationLines["app"]["app/file.al|5|1|10"] | Should -BeTrue
    }

    It "unions aggregate-only project artifacts for repository summaries" {
        $downloads = Join-Path $TestDrive "AggregateRepository"
        $sharedRoot = Join-Path $TestDrive "Shared"
        New-Item -Path $sharedRoot -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sharedRoot "File.al") `
            -Value "codeunit 1 Shared { }" -Encoding UTF8
        New-AggregateOnlyProjectArtifact -root $downloads -artifactName "artifact-a" `
            -project "A" -appId "app-a" -covered $false
        New-AggregateOnlyProjectArtifact -root $downloads -artifactName "artifact-b" `
            -project "B" -appId "app-b" -covered $true
        $buildOrder = @(@{
                buildDimensions = @(
                    @{
                        project = "A"; projectName = "A"; buildMode = "Default"
                        codeCoverageRepositorySummary = $true
                    },
                    @{
                        project = "B"; projectName = "B"; buildMode = "Default"
                        codeCoverageRepositorySummary = $true
                    }
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive

        $model.LineComplete | Should -BeTrue
        $model.Lines.Count | Should -Be 1
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "\| A \| Default \| complete \| 0\.0% \|"
        $summary | Should -Match "\| B \| Default \| complete \| 100\.0% \|"
    }
}
