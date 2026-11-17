[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in Pester test scopes')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Get-Module AnalyzeCodeCoverage | Remove-Module -Force -ErrorAction SilentlyContinue
Get-Module TestActionsHelper | Remove-Module -Force -ErrorAction SilentlyContinue
. (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot "TestActionsHelper.psm1" -Resolve) -Force
Import-Module (Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\AnalyzeCodeCoverage.psm1" -Resolve) -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageAggregateFormat.psm1" -Resolve) -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "..\Actions\.Modules\CodeCoverageReportReader.psm1" -Resolve) -Force -DisableNameChecking

Describe "AnalyzeCodeCoverage" {
    BeforeAll {
        $sourceFixtures = Join-Path $PSScriptRoot "TestArtifacts\CodeCoverage"
        $fixtures = Join-Path $TestDrive "CodeCoverageFixtures"
        Copy-Item -LiteralPath $sourceFixtures -Destination $fixtures -Recurse
        $actionName = "AnalyzeCodeCoverage"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName "$actionName.ps1"
        $scriptPath = Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\AnalyzeCodeCoverage.ps1" -Resolve

        function Publish-TestAggregate {
            Param(
                [string] $CoverageRoot,
                [hashtable] $Lines,
                [object[]] $RunDiagnostics = @()
            )

            $statusPath = Join-Path $CoverageRoot "coverage-status.json"
            $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 |
                ConvertFrom-Json |
                ConvertTo-HashTable -recurse
            for ($index = 0; $index -lt @($status.runs).Count; $index++) {
                $diagnostics = if ($index -lt $RunDiagnostics.Count) {
                    @($RunDiagnostics[$index])
                }
                else {
                    @()
                }
                $status.runs[$index].diagnostics = @($diagnostics)
            }
            Write-CodeCoverageAggregateFile `
                -path (Join-Path $CoverageRoot "coverage-aggregate.bin.gz") `
                -lines $Lines
            $status.aggregate = "coverage-aggregate.bin.gz"
            $status | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $statusPath -Encoding UTF8
        }

        Publish-TestAggregate -CoverageRoot (Join-Path $fixtures "Line\CodeCoverage") `
            -Lines @{
                src = @{
                    "src/line.codeunit.al|5|50100|11" = $true
                    "src/line.codeunit.al|5|50100|12" = $false
                }
            }
        Publish-TestAggregate -CoverageRoot (Join-Path $fixtures "MultipleRuns\CodeCoverage") `
            -Lines @{
                src = @{
                    "src/shared.report.al|3|50300|11" = $true
                    "src/shared.report.al|3|50300|21" = $false
                }
            }
        Publish-TestAggregate `
            -CoverageRoot (Join-Path $fixtures "ScopedIncomplete\Artifact\CodeCoverage") `
            -Lines @{
                "project1/app1" = @{
                    "project1/app1/helloworld.al|8|55000|20" = $true
                    "project1/app1/helloworld.al|8|55000|21" = $false
                }
            } `
            -RunDiagnostics @(
                @("Coverage method identity resolution failed for 'Project1/app1'."),
                @("Coverage method identity resolution failed for 'Project1/app1'.")
            )

        function Copy-CoverageFixture {
            Param([string] $Name, [string] $Destination)
            Copy-Item -LiteralPath (Join-Path $fixtures $Name) -Destination $Destination -Recurse
        }

        function New-RepositoryArtifact {
            Param(
                [string] $Root,
                [string] $ArtifactName,
                [string] $Project,
                [string] $ProjectName,
                [string] $BuildMode,
                [string] $SourcePath,
                [int] $HitCount
            )

            $coverageRoot = Join-Path (Join-Path $Root $ArtifactName) "CodeCoverage"
            New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
            New-Item -Path (Split-Path -Path $SourcePath -Parent) -ItemType Directory -Force | Out-Null
            if (-not (Test-Path -LiteralPath $SourcePath)) {
                Set-Content -LiteralPath $SourcePath -Value "codeunit 70000 Example { }" -Encoding UTF8
            }
            $sourceRoot = [System.IO.Path]::GetFileName((Split-Path -Path $SourcePath -Parent))
            @{
                project = $Project
                projectName = $ProjectName
                buildMode = $BuildMode
                sourceRootDetails = @(@{
                        path = $sourceRoot
                        kind = "app"
                        appId = "$Project-regular-app"
                        appName = "$Project app"
                    })
                runs = @(@{
                        appId = "$Project-app"
                        appName = "$Project tests"
                        state = "complete"
                        diagnostics = @()
                    })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8

            $rootIdentity = $sourceRoot.ToLowerInvariant()
            $lineKey = "$rootIdentity/$([System.IO.Path]::GetFileName($SourcePath).ToLowerInvariant())|5|70000|12"
            Publish-TestAggregate -CoverageRoot $coverageRoot -Lines @{
                $rootIdentity = @{
                    $lineKey = ($HitCount -gt 0)
                }
            }
        }

        function New-ExpectedDimension {
            Param([string] $Project, [string] $ProjectName = "", [string] $BuildMode = "Default")
            return @{
                project = $Project
                projectName = $ProjectName
                buildMode = $BuildMode
                codeCoverageRepositorySummary = $true
            }
        }

        function New-StreamingReaderModel {
            return @{
                SourceRoots = @("app")
                SourceRootDetails = @(@{
                        Path = "app"
                        Identity = "app"
                        Kind = "app"
                        AppId = "streaming-app"
                        AppName = "Streaming app"
                    })
            }
        }

        $script:streamingRepositoryRoot = Join-Path $TestDrive "StreamingRepository"
        $streamingAppRoot = Join-Path $script:streamingRepositoryRoot "app"
        New-Item -Path $streamingAppRoot -ItemType Directory -Force | Out-Null
        foreach ($fileName in @("Code.al", "File.al")) {
            Set-Content -LiteralPath (Join-Path $streamingAppRoot $fileName) `
                -Value "codeunit 1 Example { }" -Encoding UTF8
        }

        function Read-StreamingCoverageReport {
            Param(
                [string] $Path,
                [hashtable] $Model = (New-StreamingReaderModel),
                [hashtable] $Union = @{},
                [System.Collections.Generic.Dictionary[string,object]] $SourceMappingCache = $null
            )

            return Read-BcCoverageReport -Path $Path -Model $Model `
                -RepositoryRoot $script:streamingRepositoryRoot `
                -SemanticLineUnion $Union -SourceMappingCache $SourceMappingCache
        }

        function Resolve-TestCoverageSource {
            Param(
                [AllowEmptyString()][string] $SourcePath,
                [string] $RepositoryRoot,
                [string[]] $SourceRoots = @()
            )

            $fullRoot = [System.IO.Path]::GetFullPath(
                (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
            ).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar)
            $normalizedRoots = @(
                Get-NormalizedCoverageSourceRoots -RepositoryRoot $fullRoot `
                    -SourceRoots $SourceRoots
            )
            return Resolve-NormalizedRepositoryCoverageSource -SourcePath $SourcePath `
                -RepositoryRoot $fullRoot -NormalizedRoots $normalizedRoots
        }
    }

    It "reads the compact aggregate without the raw JSON reader" {
        $repositoryRoot = Join-Path $TestDrive "AggregateRepository"
        $appRoot = Join-Path $repositoryRoot "App"
        $coverageRoot = Join-Path $repositoryRoot ".buildartifacts\CodeCoverage"
        New-Item -Path $appRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $coverageRoot -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $appRoot "File.al") `
            -Value "codeunit 50100 Example { }" -Encoding UTF8

        $sourceRootDetails = @([ordered]@{
                path = "App"
                kind = "app"
                appId = "11111111-1111-1111-1111-111111111111"
                appName = "Regular App"
            })
        $aggregatePath = Join-Path $coverageRoot "coverage-aggregate.bin.gz"
        Write-CodeCoverageAggregateFile -path $aggregatePath -lines @{
            App = @{ "App/File.al|5|50100|11" = $true }
        }
        [ordered]@{
            project = "."
            projectName = "Project"
            buildMode = "Default"
            sourceRootDetails = $sourceRootDetails
            runs = @([ordered]@{
                    appId = "test-app"
                    appName = "Test App"
                    state = "complete"
                    diagnostics = @()
                })
            aggregate = "coverage-aggregate.bin.gz"
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8

        $model = Get-ProjectCoverageModel -CoveragePath (Split-Path $coverageRoot -Parent)

        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 1
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        New-ProjectCoverageSummary $model | Should -Match "100\.0%"
    }

    It "counts only executable lines from the published aggregate" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "Line")
        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 2
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "Line coverage"
        $summary | Should -Not -Match "Procedure coverage"
        $summary | Should -Match "### Application coverage"
        $summary | Should -Match "\| Line app \| 1/2 \| 50% \|"
    }

    It "OR-unions executable lines from multiple compacted runs" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "MultipleRuns")
        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 2
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "Top 10 uncovered objects"
        $summary | Should -Match "Report 50300"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Not -Match "src/Shared\.Report\.al"
        $summary | Should -Not -Match "\| Source \|"
    }

    It "treats missing and corrupt aggregates as incomplete without throwing" {
        $missingRoot = Join-Path $TestDrive "MissingAggregate"
        Copy-CoverageFixture -Name "Line" -Destination $missingRoot
        Remove-Item -LiteralPath (Join-Path $missingRoot "CodeCoverage\coverage-aggregate.bin.gz")
        { Get-ProjectCoverageModel -CoveragePath $missingRoot } | Should -Not -Throw
        $missing = Get-ProjectCoverageModel -CoveragePath $missingRoot
        $missing.Reasons | Should -Not -BeNullOrEmpty
        $missing.Reasons -join " " | Should -Match "aggregate is invalid"

        $corruptRoot = Join-Path $TestDrive "CorruptAggregate"
        Copy-CoverageFixture -Name "Line" -Destination $corruptRoot
        Set-Content -LiteralPath (Join-Path $corruptRoot "CodeCoverage\coverage-aggregate.bin.gz") `
            -Value "bad" -Encoding UTF8
        { Get-ProjectCoverageModel -CoveragePath $corruptRoot } | Should -Not -Throw
        $corrupt = Get-ProjectCoverageModel -CoveragePath $corruptRoot
        $corrupt.Reasons | Should -Not -BeNullOrEmpty
        $corrupt.Reasons -join " " | Should -Match "aggregate is invalid"
    }

    Context "BC JSON streaming reader" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        It "reads the required root contract" {
            $path = Join-Path $fixtures "Line\CodeCoverage\line-app\coverage.bc.json"
            $result = Read-StreamingCoverageReport -Path $path
            @($result.Data.Keys | Sort-Object) | Should -Be @(
                "complete", "coverageMode", "diagnostics", "schemaVersion"
            )
        }

        It "rejects malformed documents and invalid root contracts" -TestCases @(
            @{
                Name = "array root"
                Json = '[]'
                Expected = "*corrupt or invalid*"
            },
            @{
                Name = "truncated"
                Json = '{"schemaVersion":"1.0","coverageMode":"line"'
                Expected = "*corrupt or invalid*"
            },
            @{
                Name = "trailing"
                Json = '{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[]} false'
                Expected = "*corrupt or invalid*"
            },
            @{
                Name = "missing schema"
                Json = '{"coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[]}'
                Expected = "*schemaVersion*"
            },
            @{
                Name = "numeric schema"
                Json = '{"schemaVersion":1,"coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[]}'
                Expected = "*schemaVersion*"
            },
            @{
                Name = "Boolean mode"
                Json = '{"schemaVersion":"1.0","coverageMode":true,"complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[]}'
                Expected = "*mode*"
            },
            @{
                Name = "string completeness"
                Json = '{"schemaVersion":"1.0","coverageMode":"line","complete":"true","diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[]}'
                Expected = "*completeness*"
            },
            @{
                Name = "invalid diagnostics"
                Json = '{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":{},"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[]}'
                Expected = "*does not match schemaVersion*"
            },
            @{
                Name = "invalid methods root"
                Json = '{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":{},"lines":[]}'
                Expected = "*does not match schemaVersion*"
            }
        ) {
            Param($Name, $Json, $Expected)

            $path = Join-Path $TestDrive "$Name.json"
            Set-Content -LiteralPath $path -Value $Json -Encoding UTF8
            { Read-StreamingCoverageReport -Path $path } | Should -Throw $Expected
        }

        It "validates but does not materialize unused methods and procedure edges" {
            $path = Join-Path $TestDrive "unused-structures.json"
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[{"unexpected":true}],"methods":[{"unexpected":true}],"lines":[]}
'@

            $result = Read-StreamingCoverageReport -Path $path
            @($result.Data.Keys | Sort-Object) | Should -Be @(
                "complete", "coverageMode", "diagnostics", "schemaVersion"
            )
        }

        It "rejects duplicate required root properties on the streaming path" `
            -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            $path = Join-Path $TestDrive "duplicate-root.json"
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
{
  "schemaVersion": "1.0",
  "coverageMode": "line",
  "coverageMode": "all",
  "complete": true,
  "diagnostics": [],
  "sources": [],
  "tests": [],
  "procedureEdges": [],
  "methods": [],
  "lines": []
}
'@
            { Read-StreamingCoverageReport -Path $path } |
                Should -Throw "*does not match schemaVersion*"
        }

        It "retains diagnostics and OR-unions duplicate line identities" {
            $path = Join-Path $TestDrive "duplicate-lines.json"
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
{
  "schemaVersion": "1.0",
  "coverageMode": "line",
  "complete": false,
  "diagnostics": ["Coverage method identity resolution failed for 'app'."],
  "sources": ["Code.al"],
  "tests": [],
  "procedureEdges": [],
  "methods": [],
  "lines": [
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":0,"status":0,"sourcePath":"Code.al"},
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"Code.al"}
  ]
}
'@
            $union = @{}
            $result = Read-StreamingCoverageReport -Path $path -Union $union

            $result.Data.complete | Should -BeFalse
            $result.Data.diagnostics | Should -Be @(
                "Coverage method identity resolution failed for 'app'."
            )
            $result.ExtractedLineCount | Should -Be 2
            $result.NewLineCount | Should -Be 1
            $facts = $union["app"]
            $facts.Count | Should -Be 1
            @($facts.Values)[0] | Should -BeTrue
        }

        It "reuses source-path mappings across reports" {
            $repositoryRoot = Join-Path $TestDrive "MappingCache"
            $appRoot = Join-Path $repositoryRoot "app"
            New-Item -Path $appRoot -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $appRoot "File.al") `
                -Value "codeunit 1 Example { }" -Encoding UTF8
            $reportJson = @'
{
  "schemaVersion": "1.0",
  "coverageMode": "line",
  "complete": true,
  "diagnostics": [],
  "sources": ["File.al"],
  "tests": [],
  "procedureEdges": [],
  "methods": [],
  "lines": [
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"File.al"}
  ]
}
'@
            $firstPath = Join-Path $TestDrive "cache-first.json"
            $secondPath = Join-Path $TestDrive "cache-second.json"
            Set-Content -LiteralPath $firstPath -Value $reportJson -Encoding UTF8
            Set-Content -LiteralPath $secondPath -Value $reportJson -Encoding UTF8

            InModuleScope CodeCoverageReportReader -Parameters @{
                FirstPath = $firstPath
                SecondPath = $secondPath
                RepositoryRoot = $repositoryRoot
                Model = (New-StreamingReaderModel)
            } {
                Mock Resolve-NormalizedRepositoryCoverageSource {
                    return @{
                        Included = $true
                        Identity = "app/file.al"
                        SourceRootIndex = 0
                    }
                }
                $cache = [System.Collections.Generic.Dictionary[string,object]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )

                foreach ($path in @($FirstPath, $SecondPath)) {
                    $result = Read-BcCoverageReport -Path $path -Model $Model `
                        -RepositoryRoot $RepositoryRoot -SemanticLineUnion @{} `
                        -SourceMappingCache $cache
                    $result.Data.complete | Should -BeTrue
                }

                $cache.Count | Should -Be 1
                Should -Invoke Resolve-NormalizedRepositoryCoverageSource -Times 1 -Exactly
            }
        }

        It "streams accepted lines directly into an aggregate union without retaining per-run lines" `
            -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            $reportPath = Join-Path $TestDrive "direct-union.json"
            Set-Content -LiteralPath $reportPath -Encoding UTF8 -Value @'
{
  "schemaVersion": "1.0",
  "coverageMode": "line",
  "complete": true,
  "diagnostics": [],
  "sources": ["Code.al"],
  "tests": [],
  "procedureEdges": [],
  "methods": [],
  "lines": [
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":0,"status":0,"sourcePath":"Code.al"},
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"Code.al"},
    {"objectType":5,"objectId":1,"lineNumber":11,"lineType":3,"methodId":1,"hitCount":0,"status":0,"sourcePath":"Code.al"}
  ]
}
'@
            $union = @{}

            $result = Read-StreamingCoverageReport -Path $reportPath -Union $union

            $result.NewLineCount | Should -Be 2
            $union.Count | Should -Be 1
            $union["app"].Count | Should -Be 2
            @($union["app"].Values | Where-Object { $_ }).Count | Should -Be 1
        }
    }

    It "escapes report-derived Markdown and HTML and bounds values" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $unsafe = "A|B`r`n<script>& [click](https://example.invalid) **bold** ![image](x) ``code``" + ("x" * 300)
        $safe = ConvertTo-SafeCoverageText $unsafe
        $safe | Should -Match "A\\\|B &lt;script&gt;&amp;"
        $safe | Should -Not -Match "[`r`n]"
        $safe | Should -Match "\\\[click\\\]\\\(https://example\.invalid\\\)"
        $safe | Should -Match "\\\*\\\*bold\\\*\\\*"
        $safe | Should -Not -Match "(?<!\\)!\["
        $safe.Length | Should -BeLessThan 190

        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "Line")
        $model.ProjectName = $unsafe
        $model.Apps[0].AppName = $unsafe
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Not -Match "<script>"
        $summary | Should -Match "&lt;script&gt;"

        $model.Lines = @{ "bad|<script>.al|5|1|10" = $false }
        { New-ProjectCoverageSummary $model } | Should -Not -Throw
        (New-ProjectCoverageSummary $model) | Should -Match "bad\\\|&lt;script&gt;"
        (New-ProjectCoverageSummary $model) | Should -Not -Match "bad\\\|&lt;script&gt;\.al"
    }

    It "keeps a missing expected repository artifact visible and hides repository union metrics" {
        $downloads = Join-Path $TestDrive "MissingExpected"
        New-Item -Path $downloads -ItemType Directory | Out-Null
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "ExpectedProject" -ProjectName "Expected project")
                )
            }) | ConvertTo-Json -Depth 10
        $model = Get-RepositoryCoverageModel -CoveragePath $downloads -BuildOrderJson $buildOrder
        $model.Reasons | Should -Not -BeNullOrEmpty
        $model.Projects.Count | Should -Be 1
        $model.Apps.Count | Should -Be 0
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "Expected project"
        $summary | Should -Match "Coverage is unavailable"
        $summary | Should -Match "artifact is missing"
        $summary | Should -Match "\*\*Line coverage:\*\* unavailable"
        $summary | Should -Not -Match "\*\*Line coverage:\*\* [0-9]"
        $summary | Should -Not -Match "Top 10 uncovered objects"
        $summary | Should -Match "No regular apps were available"
        $summary | Should -Not -Match "Test-app runs|Per-test-app runs"
    }

    It "requires artifacts from every dependency depth" {
        $downloads = Join-Path $TestDrive "MultipleDepths"
        $sourcePath = Join-Path $TestDrive "DepthOne\Depth.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-depth-one" -Project "DepthOne" `
            -ProjectName "Depth one" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1
        $buildOrder = ConvertTo-Json -Depth 10 -InputObject @(
            @{ buildDimensions = @((New-ExpectedDimension -Project "DepthOne" -ProjectName "Depth one")) },
            @{ buildDimensions = @((New-ExpectedDimension -Project "DepthTwo" -ProjectName "Depth two")) }
        )

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder

        $model.Reasons | Should -Not -BeNullOrEmpty
        $model.Projects.Count | Should -Be 2
        @($model.Projects | Where-Object { $_.Project -eq "DepthTwo" })[0].Reasons |
            Should -Contain "Expected coverage artifact is missing."
    }

    It "unions cross-project facts instead of adding project totals" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $downloads = Join-Path $TestDrive "RepositoryUnion"
        $sourcePath = Join-Path $TestDrive "Shared\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-a" -Project "A" `
            -ProjectName "Project A" -BuildMode "Default" -SourcePath $sourcePath -HitCount 0
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-b" -Project "B" `
            -ProjectName "Project B" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "A" -ProjectName "Project A"),
                    (New-ExpectedDimension -Project "B" -ProjectName "Project B")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads -BuildOrderJson $buildOrder
        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 1
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "\*\*Line coverage:"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Match "Project A"
        $summary | Should -Match "Project B"
    }

    It "deduplicates the same repository line across build modes" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $downloads = Join-Path $TestDrive "BuildModeUnion"
        $sourcePath = Join-Path $TestDrive "Shared\BuildMode.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 0
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-clean" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Clean" -SourcePath $sourcePath -HitCount 1
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Default"),
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Clean")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder

        $model.Reasons | Should -BeNullOrEmpty
        $model.Projects.Count | Should -Be 2
        $model.Lines.Count | Should -Be 1
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $model.Apps.Count | Should -Be 1
        (Get-CoverageMetrics $model.Apps[0].Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $model.Apps[0].Lines).Total | Should -Be 1
        $summary = New-RepositoryCoverageSummary $model
        @([regex]::Matches($summary, "\| Tests \| Tests app \| 1/1 \| 100% \|")).Count |
            Should -Be 1
    }

    It "marks a repository app unavailable when one required execution fails" {
        $downloads = Join-Path $TestDrive "BlockedApplication"
        $sourcePath = Join-Path $TestDrive "Blocked\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-clean" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Clean" -SourcePath $sourcePath -HitCount 1
        $failedStatusPath = Join-Path $downloads "artifact-clean\CodeCoverage\coverage-status.json"
        $failedStatus = Get-Content -LiteralPath $failedStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $failedStatus.runs[0].state = "failed"
        $failedStatus | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $failedStatusPath -Encoding UTF8
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Default"),
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Clean")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder
        $summary = New-RepositoryCoverageSummary $model

        $model.Apps.Count | Should -Be 1
        $model.Reasons | Should -Not -BeNullOrEmpty
        $summary | Should -Match "\| Tests \| Tests app \| unavailable \| unavailable \|"
        $summary | Should -Not -Match "\| Tests \| Tests app \| 1/1 \|"
    }

    It "marks known repository apps unavailable when a required dimension is missing" {
        $downloads = Join-Path $TestDrive "MissingApplicationDimension"
        $sourcePath = Join-Path $TestDrive "MissingDimension\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Default"),
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Clean")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder
        $summary = New-RepositoryCoverageSummary $model

        $model.Apps.Count | Should -Be 1
        $model.Reasons | Should -Not -BeNullOrEmpty
        $summary | Should -Match "\| Tests \| Tests app \| unavailable \| unavailable \|"
    }

    It "does not calculate repository app coverage from a partial set of metadata-aware dimensions" {
        $downloads = Join-Path $TestDrive "OlderApplicationDimension"
        $sourcePath = Join-Path $TestDrive "OlderDimension\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-clean" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Clean" -SourcePath $sourcePath -HitCount 1
        $olderStatusPath = Join-Path $downloads "artifact-clean\CodeCoverage\coverage-status.json"
        $olderStatus = Get-Content -LiteralPath $olderStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $olderStatus.PSObject.Properties.Remove("sourceRootDetails")
        $olderStatus | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $olderStatusPath -Encoding UTF8
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Default"),
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Clean")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder
        $summary = New-RepositoryCoverageSummary $model

        $model.Apps.Count | Should -Be 1
        $model.Reasons | Should -Not -BeNullOrEmpty
        $summary | Should -Match "\| Tests \| Tests app \| unavailable \| unavailable \|"
    }

    It "sorts and escapes project application rows deterministically" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "MultipleRuns")
        $model.Apps = @(
            @{ AppName = "Zulu app"; AppId = "2"; RootIdentity = "z"; Lines = @{} },
            @{ AppName = "A|<script> app"; AppId = "1"; RootIdentity = "a"; Lines = @{} }
        )

        $summary = New-ProjectCoverageSummary $model

        $summary | Should -Match "(?s)### Application coverage.*A\\\|&lt;script&gt; app.*Zulu app"
        $summary | Should -Not -Match "<script>"
    }

    It "keeps duplicate regular app IDs at different roots as separate rows" {
        $projectModels = @(@{
                Project = "Apps"
                ProjectName = "Apps"
                Reasons = @()
                Apps = @(
                    @{
                        AppId = "duplicate"
                        AppName = "Localized app"
                        RootIdentity = "src/one"
                        Lines = @{ "src/one/App.Codeunit.al|5|70000|10" = $true }
                    },
                    @{
                        AppId = "duplicate"
                        AppName = "Localized app"
                        RootIdentity = "src/two"
                        Lines = @{ "src/two/App.Codeunit.al|5|70000|10" = $true }
                    }
                )
            })

        InModuleScope AnalyzeCodeCoverage -Parameters @{ ProjectModels = $projectModels } {
            param($ProjectModels)

            $applications = @(Get-RepositoryApplications -ProjectModels $ProjectModels)

            $applications.Count | Should -Be 2
            @($applications | ForEach-Object { $_.RootIdentity } | Sort-Object) |
                Should -Be @("src/one", "src/two")
        }
    }

    It "shows complete project rates but no repository metrics when another project is incomplete" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $downloads = Join-Path $TestDrive "MixedRepository"
        $sourcePath = Join-Path $TestDrive "Mixed\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-a" -Project "A" `
            -ProjectName "Project A" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "A" -ProjectName "Project A"),
                    (New-ExpectedDimension -Project "Missing" -ProjectName "Missing project")
                )
            }) | ConvertTo-Json -Depth 10
        $model = Get-RepositoryCoverageModel -CoveragePath $downloads -BuildOrderJson $buildOrder
        $summary = New-RepositoryCoverageSummary $model
        $model.Reasons | Should -Not -BeNullOrEmpty
        $summary | Should -Match "Project A.*100.0%"
        $summary | Should -Match "Missing project"
        $summary | Should -Match "\*\*Line coverage:\*\* unavailable"
        $summary | Should -Not -Match "\*\*Line coverage:\*\* [0-9]"
        $summary | Should -Not -Match "Top 10 uncovered objects"
        $summary | Should -Not -Match "Per-test-app runs"
    }

    It "maps only source paths that resolve to existing repository files" {
        (Resolve-TestCoverageSource -SourcePath "" -RepositoryRoot $TestDrive).Included | Should -BeFalse
        (Resolve-TestCoverageSource -SourcePath "relative\File.al" -RepositoryRoot $TestDrive).Included | Should -BeFalse
        $outside = Join-Path (Split-Path $TestDrive -Parent) "outside\File.al"
        (Resolve-TestCoverageSource -SourcePath $outside -RepositoryRoot $TestDrive).Included | Should -BeFalse
        $inside = Join-Path $TestDrive "inside\File.al"
        New-Item -Path (Split-Path $inside -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $inside -Value "codeunit 1 Inside { }" -Encoding UTF8
        $resolved = Resolve-TestCoverageSource -SourcePath $inside `
            -RepositoryRoot $TestDrive -SourceRoots @("inside")
        $resolved.Included | Should -BeTrue
        $resolved.Identity | Should -Be "inside/file.al"
    }

    It "decodes unprefixed exporter paths only against the primary source root" {
        $parentFile = Join-Path $TestDrive "src\Thing.al"
        $nestedFile = Join-Path $TestDrive "src\App\Thing.al"
        foreach ($path in @($parentFile, $nestedFile)) {
            New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $path -Value "codeunit 1 Thing { }" -Encoding UTF8
        }

        $resolved = Resolve-TestCoverageSource -SourcePath "Thing.al" `
            -RepositoryRoot $TestDrive -SourceRoots @("src", "src/App")

        $resolved.Included | Should -BeTrue
        $resolved.Identity | Should -Be "src/thing.al"
    }

    It "decodes external-N paths using exact source-root order and rejects invalid mappings" {
        $roots = @("src/Primary", "src/app1", "src/app1.Test")
        $files = @(
            "src/Primary/Primary.al",
            "src/app1/App.al",
            "src/app1.Test/App.Test.al"
        )
        foreach ($relativePath in $files) {
            $path = Join-Path $TestDrive $relativePath
            New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $path -Value "codeunit 1 Example { }" -Encoding UTF8
        }

        (Resolve-TestCoverageSource -SourcePath "Primary.al" `
                -RepositoryRoot $TestDrive -SourceRoots $roots).Identity |
            Should -Be "src/primary/primary.al"
        (Resolve-TestCoverageSource -SourcePath "external-1\app1\App.al" `
                -RepositoryRoot $TestDrive -SourceRoots $roots).Identity |
            Should -Be "src/app1/app.al"
        (Resolve-TestCoverageSource -SourcePath "external-2\APP1.TEST\App.Test.al" `
                -RepositoryRoot $TestDrive -SourceRoots $roots).Identity |
            Should -Be "src/app1.test/app.test.al"

        foreach ($invalidSource in @(
                "external-3\missing\App.al",
                "external-1\wrong\App.al",
                "external-1\app1\Missing.al",
                "external-1\app1\..\Primary\Primary.al"
            )) {
            $invalid = Resolve-TestCoverageSource -SourcePath $invalidSource `
                -RepositoryRoot $TestDrive -SourceRoots $roots
            $invalid.Included | Should -BeFalse
        }
    }

    It "does not remap an unprefixed exporter path to a non-primary root" {
        foreach ($relativePath in @("Tests\Marker.al", "Actions\Marker.al")) {
            $path = Join-Path $TestDrive $relativePath
            New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $path -Value "codeunit 1 Marker { }" -Encoding UTF8
        }

        $resolved = Resolve-TestCoverageSource -SourcePath "Actions\Marker.al" `
            -RepositoryRoot $TestDrive -SourceRoots @("Tests", "Actions")

        $resolved.Included | Should -BeFalse
    }

    It "includes incomplete run lines and shows distinct diagnostics as warnings" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $coveragePath = Join-Path $fixtureRoot "Artifact"

        $model = Get-ProjectCoverageModel -CoveragePath $coveragePath

        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 2
        $lineMetrics = Get-CoverageMetrics $model.Lines
        $lineMetrics.Covered | Should -Be 1
        $lineMetrics.Total | Should -Be 2
        $model.Apps.Count | Should -Be 1
        $model.Apps[0].AppName | Should -Be "app1"
        (Get-CoverageMetrics $model.Apps[0].Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $model.Apps[0].Lines).Total | Should -Be 2
        $model.IncompleteRuns | Should -Be @("App1.abc.Test", "app1.Test")
        $model.Diagnostics | Should -Be @(
            "Coverage method identity resolution failed for 'Project1/app1'."
        )

        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "50\.0%"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Match "\| app1 \| 1/2 \| 50% \|"
        $summary | Should -Not -Match "\| App1\.abc\.Test \| [0-9]+/"
        $summary | Should -Not -Match "\| app1\.Test \| [0-9]+/"
        $summary | Should -Match "globally incomplete coverage"
        $summary | Should -Match "App1\.abc\.Test"
        $summary | Should -Match "app1\.Test"
        $summary | Should -Match "method identity resolution failed"
        $summary | Should -Not -Match "\| Details \|"
        $summary | Should -Not -Match "97\."
        $summary | Should -Not -Match "437/447"
    }

    It "renders no application rows for an older status without root metadata" {
        $root = Join-Path $TestDrive "OlderStatus"
        Copy-CoverageFixture -Name "Line" -Destination $root
        $statusPath = Join-Path $root "CodeCoverage\coverage-status.json"
        $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.PSObject.Properties.Remove("sourceRootDetails")
        $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath -Encoding UTF8
        $model = Get-ProjectCoverageModel -CoveragePath $root
        $summary = New-ProjectCoverageSummary $model

        $model.Reasons | Should -Not -BeNullOrEmpty
        $model.Apps.Count | Should -Be 0
        $summary | Should -Match "### Application coverage"
        $summary | Should -Match "No regular apps were available"
        $summary | Should -Not -Match "\| Line Tests \| [0-9]+/"
    }

    It "escapes and bounds diagnostic details in project and repository warnings" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $coveragePath = Join-Path $fixtureRoot "Artifact"
        $diagnostic = "Coverage method identity resolution failed for 'Project1/app1': " +
            "Project1/app1/HelloWorld.al(5,45): error AL0247: target page is missing"

        $projectModel = Get-ProjectCoverageModel -CoveragePath $coveragePath
        $projectModel.Diagnostics = @($diagnostic)
        $projectSummary = New-ProjectCoverageSummary $projectModel

        $projectSummary | Should -Match "AlTool reported coverage diagnostics"
        $projectSummary | Should -Match "AL0247"
        $projectSummary | Should -Match "HelloWorld\.al"
        $projectSummary | Should -Not -Match "\| Details \|"
        $projectSummary | Should -Not -Match "\| Source \|"

        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Project1" -ProjectName "Project 1")
                )
            }) | ConvertTo-Json -Depth 10
        $repositoryModel = Get-RepositoryCoverageModel -CoveragePath $coveragePath `
            -BuildOrderJson $buildOrder
        $repositoryModel.Diagnostics = @($diagnostic)
        $repositorySummary = New-RepositoryCoverageSummary $repositoryModel

        $repositorySummary | Should -Match "AlTool reported coverage diagnostics"
        $repositorySummary | Should -Match "AL0247"
        $repositorySummary | Should -Match "HelloWorld\.al"
        $repositorySummary | Should -Not -Match "\| Details \|"
        $repositorySummary | Should -Not -Match "\| Source \|"
    }

    It "unions admitted incomplete reports for repository coverage" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Project1" -ProjectName "Project 1")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath (Join-Path $fixtureRoot "Artifact") `
            -BuildOrderJson $buildOrder

        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 2
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $model.Apps.Count | Should -Be 1
        $application = $model.Apps[0]
        $application.AppName | Should -Be "app1"
        (Get-CoverageMetrics $application.Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $application.Lines).Total | Should -Be 2
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "50\.0%"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Match "\| Project 1 \| app1 \| 1/2 \| 50% \|"
        $summary | Should -Not -Match "\| Project 1 \| App1\.abc\.Test \|"
        $summary | Should -Not -Match "\| Project 1 \| app1\.Test \|"
        $summary | Should -Match "globally incomplete coverage"
        $summary | Should -Match "method identity resolution failed"
        $summary | Should -Not -Match "\| Details \|"
    }

    It "keeps duplicate app IDs in different projects as separate repository facts" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $downloads = Join-Path $TestDrive "DuplicateIds"
        $firstSource = Join-Path $TestDrive "W1\Shared.Codeunit.al"
        $secondSource = Join-Path $TestDrive "DK\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-w1" -Project "W1" `
            -ProjectName "W1" -BuildMode "Default" -SourcePath $firstSource -HitCount 1
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-dk" -Project "DK" `
            -ProjectName "DK" -BuildMode "Default" -SourcePath $secondSource -HitCount 1
        foreach ($statusPath in @(Get-ChildItem -LiteralPath $downloads -Filter "coverage-status.json" -File -Recurse)) {
            $status = Get-Content -LiteralPath $statusPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $status.sourceRootDetails[0].appId = "duplicate-app-id"
            $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath.FullName -Encoding UTF8
        }
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "W1" -ProjectName "W1"),
                    (New-ExpectedDimension -Project "DK" -ProjectName "DK")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder

        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 2
        $model.Apps.Count | Should -Be 2
    }

    It "honors project summary settings" {
        (Test-CodeCoverageSummaryRequested -Settings @{ useSeparateTestAction = @{ codeCoverageSummary = "project" } } -Scope project) | Should -BeTrue
        (Test-CodeCoverageSummaryRequested -Settings @{ useSeparateTestAction = @{ codeCoverageSummary = "both" } } -Scope project) | Should -BeTrue
        (Test-CodeCoverageSummaryRequested -Settings @{ useSeparateTestAction = @{ codeCoverageSummary = "repository" } } -Scope project) | Should -BeFalse
    }

    It "matches the composite action contract" {
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript `
            -outputs ([ordered]@{}) -DefaultShell powershell
    }

    It "appends a project summary only when project settings request it" {
        $summaryPath = Join-Path $TestDrive "step-summary.md"
        $previousWorkspace = $env:GITHUB_WORKSPACE
        $previousSummary = $env:GITHUB_STEP_SUMMARY
        $previousSettings = $env:Settings
        try {
            $env:GITHUB_WORKSPACE = $TestDrive
            $env:GITHUB_STEP_SUMMARY = $summaryPath
            $env:Settings = '{"useSeparateTestAction":{"codeCoverageSummary":"none"}}'
            & $scriptPath -scope project -project LineProject -coveragePath (Join-Path $fixtures "Line")
            Test-Path -LiteralPath $summaryPath | Should -BeFalse

            $env:Settings = '{"useSeparateTestAction":{"codeCoverageSummary":"both"}}'
            $analysisLog = & $scriptPath -scope project -project LineProject `
                -coveragePath (Join-Path $fixtures "Line") *>&1 | Out-String
            $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
            $analysisLog | Should -Not -Match "Code coverage analysis detail:"
            $summary | Should -Match "Line coverage"
            $summary | Should -Not -Match "repository source path could not be validated"
        }
        finally {
            $env:GITHUB_WORKSPACE = $previousWorkspace
            $env:GITHUB_STEP_SUMMARY = $previousSummary
            $env:Settings = $previousSettings
        }
    }

    It "appends a repository summary from expected downloaded artifacts" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $downloads = Join-Path $TestDrive "ActionRepository"
        $sourcePath = Join-Path $TestDrive "Shared\Action.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-action" -Project "ActionProject" `
            -ProjectName "Action project" -BuildMode "Default" -SourcePath $sourcePath `
            -HitCount 1
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "ActionProject" -ProjectName "Action project")
                )
            }) | ConvertTo-Json -Depth 10 -Compress
        $summaryPath = Join-Path $TestDrive "repository-summary.md"
        $previousWorkspace = $env:GITHUB_WORKSPACE
        $previousSummary = $env:GITHUB_STEP_SUMMARY
        try {
            $env:GITHUB_WORKSPACE = $TestDrive
            $env:GITHUB_STEP_SUMMARY = $summaryPath

            & $scriptPath -scope repository -coveragePath $downloads -buildOrderJson $buildOrder

            $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
            $summary | Should -Match "Repository code coverage"
            $summary | Should -Match "Action project"
            $summary | Should -Match "100\.0%"
        }
        finally {
            $env:GITHUB_WORKSPACE = $previousWorkspace
            $env:GITHUB_STEP_SUMMARY = $previousSummary
        }
    }

}
