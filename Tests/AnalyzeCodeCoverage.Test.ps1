[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in Pester test scopes')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Get-Module AnalyzeCodeCoverage | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\AnalyzeCodeCoverage.psm1" -Resolve) -Force -DisableNameChecking

Describe "AnalyzeCodeCoverage" {
    BeforeAll {
        $fixtures = Join-Path $PSScriptRoot "TestArtifacts\CodeCoverage"
        $actionYamlPath = Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\action.yaml" -Resolve
        $modulePath = Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\AnalyzeCodeCoverage.psm1" -Resolve
        $scriptPath = Join-Path $PSScriptRoot "..\Actions\AnalyzeCodeCoverage\AnalyzeCodeCoverage.ps1" -Resolve

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
                [int] $HitCount,
                [bool] $MethodCovered
            )

            $coverageRoot = Join-Path (Join-Path $Root $ArtifactName) "CodeCoverage"
            $reportRoot = Join-Path $coverageRoot "test-app"
            New-Item -Path $reportRoot -ItemType Directory -Force | Out-Null
            New-Item -Path (Split-Path -Path $SourcePath -Parent) -ItemType Directory -Force | Out-Null
            if (-not (Test-Path -LiteralPath $SourcePath)) {
                Set-Content -LiteralPath $SourcePath -Value "codeunit 70000 Example { }" -Encoding UTF8
            }
            $sourceRoot = [System.IO.Path]::GetFileName((Split-Path -Path $SourcePath -Parent))
            @{
                project = $Project
                projectName = $ProjectName
                buildMode = $BuildMode
                mode = "all"
                formats = @("bc-json")
                sourceRoots = @($sourceRoot)
                sourceRootDetails = @(@{
                        path = $sourceRoot
                        kind = "app"
                        appId = "$Project-regular-app"
                        appName = "$Project app"
                    })
                runs = @(@{
                        appId = "$Project-app"
                        appName = "$Project tests"
                        outputDirectory = "CodeCoverage/test-app"
                        state = "complete"
                    })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $coverageRoot "coverage-status.json") -Encoding UTF8

            $edges = @()
            if ($MethodCovered) {
                $edges = @(@{ objectType = 5; objectId = 70000; methodId = 100 + $HitCount; testId = 1 })
            }
            @{
                schemaVersion = "1.0"
                coverageMode = "all"
                complete = $true
                diagnostics = @()
                sources = @($SourcePath)
                tests = @(@{ testId = 1; codeunitId = 80000; methodId = 1; methodName = "Test"; owningAppId = "$Project-app" })
                procedureEdges = $edges
                methods = @(@{
                        objectType = 5
                        objectId = 70000
                        methodId = 100 + $HitCount
                        name = "SharedMethod"
                        startLine = 10
                        endLine = 15
                        sourcePath = $SourcePath
                    })
                lines = @(@{
                        objectType = 5
                        objectId = 70000
                        lineNumber = 12
                        lineType = 3
                        methodId = 100 + $HitCount
                        hitCount = $HitCount
                        status = if ($HitCount -gt 0) { 1 } else { 0 }
                        sourcePath = $SourcePath
                    })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $reportRoot "coverage.bc.json") -Encoding UTF8
        }

        function New-ExpectedDimension {
            Param([string] $Project, [string] $ProjectName = "", [string] $BuildMode = "Default", [string] $Mode = "all")
            return @{
                project = $Project
                projectName = $ProjectName
                buildMode = $BuildMode
                codeCoverageExpected = $true
                codeCoverageRepositorySummary = $true
                codeCoverageMode = $Mode
                codeCoverageFormats = @("bc-json")
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
    }

    It "parses the actual schema and counts only executable lines in line mode" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "Line")
        $model.Complete | Should -BeTrue
        $model.LineComplete | Should -BeTrue
        $model.Mode | Should -Be "line"
        $model.Lines.Count | Should -Be 2
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $model.Runs[0].LineComplete | Should -BeTrue
        $model.Runs[0].ContainsKey("Lines") | Should -BeFalse
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "Line coverage"
        $summary | Should -Not -Match "Procedure coverage"
        $summary | Should -Match "### Application coverage"
        $summary | Should -Match "\| Line app \| 1/2 \| 50% \|"
    }

    It "does not expose procedure-only reports as coverage" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "Procedure")
        $model.Complete | Should -BeFalse
        $model.LineComplete | Should -BeFalse
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "\*\*Line coverage:\*\* unavailable"
        $summary | Should -Not -Match "\*\*Procedure coverage"
        $summary | Should -Match "No regular apps were available"
    }

    It "OR-unions executable lines from historical all-mode reports" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "All")
        $model.Complete | Should -BeTrue
        $model.LineComplete | Should -BeTrue
        $model.Runs.Count | Should -Be 2
        $model.Lines.Count | Should -Be 2
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "Top 10 uncovered objects"
        $summary | Should -Match "Report 50300"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Not -Match "src/Shared\.Report\.al"
        $summary | Should -Not -Match "\| Source \|"
    }

    It "renders status only when only Cobertura was requested" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "CoberturaOnly")
        $model.Complete | Should -BeFalse
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "Coverage data is incomplete"
        $summary | Should -Match "action logs and raw CodeCoverage artifact"
        $summary | Should -Not -Match "bc-json coverage format"
        $summary | Should -Match "No regular apps were available"
        $summary | Should -Not -Match "%"
        $summary | Should -Not -Match "Top 10 uncovered objects"
        $summary | Should -Not -Match "executable lines"
    }

    It "treats missing and corrupt reports as incomplete without throwing" {
        $missingRoot = Join-Path $TestDrive "MissingReport"
        Copy-CoverageFixture -Name "Line" -Destination $missingRoot
        Remove-Item -LiteralPath (Join-Path $missingRoot "CodeCoverage\line-app\coverage.bc.json")
        { Get-ProjectCoverageModel -CoveragePath $missingRoot } | Should -Not -Throw
        $missing = Get-ProjectCoverageModel -CoveragePath $missingRoot
        $missing.Complete | Should -BeFalse
        $missing.Reasons -join " " | Should -Match "missing"

        $corruptRoot = Join-Path $TestDrive "CorruptReport"
        Copy-CoverageFixture -Name "Line" -Destination $corruptRoot
        Set-Content -LiteralPath (Join-Path $corruptRoot "CodeCoverage\line-app\coverage.bc.json") -Value "{bad" -Encoding UTF8
        { Get-ProjectCoverageModel -CoveragePath $corruptRoot } | Should -Not -Throw
        $corrupt = Get-ProjectCoverageModel -CoveragePath $corruptRoot
        $corrupt.Complete | Should -BeFalse
        $corrupt.Reasons -join " " | Should -Match "corrupt"
    }

    It "rejects unsupported schema versions and coverage modes" {
        foreach ($case in @(
                @{ Name = "Schema"; Property = "schemaVersion"; Value = "2.0"; Match = "schemaVersion" },
                @{ Name = "Mode"; Property = "coverageMode"; Value = "branch"; Match = "mode" }
            )) {
            $caseRoot = Join-Path $TestDrive $case.Name
            Copy-CoverageFixture -Name "Line" -Destination $caseRoot
            $reportPath = Join-Path $caseRoot "CodeCoverage\line-app\coverage.bc.json"
            $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.($case.Property) = $case.Value
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
            $model = Get-ProjectCoverageModel -CoveragePath $caseRoot
            $model.Complete | Should -BeFalse
            $model.Reasons -join " " | Should -Match $case.Match
            (New-ProjectCoverageSummary $model) | Should -Not -Match "%"
        }
    }

    It "requires the report mode to match the requested status mode" {
        $root = Join-Path $TestDrive "MismatchedMode"
        Copy-CoverageFixture -Name "Line" -Destination $root
        $reportPath = Join-Path $root "CodeCoverage\line-app\coverage.bc.json"
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.coverageMode = "procedure"
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        $model = Get-ProjectCoverageModel -CoveragePath $root
        $model.Complete | Should -BeFalse
        $model.Reasons -join " " | Should -Match "does not match"
        (New-ProjectCoverageSummary $model) | Should -Not -Match "%"
    }

    It "does not let the raw global completeness flag suppress regular-app lines" {
        $root = Join-Path $TestDrive "IncompleteReport"
        Copy-CoverageFixture -Name "Line" -Destination $root
        $reportPath = Join-Path $root "CodeCoverage\line-app\coverage.bc.json"
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.complete = $false
        $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        $model = Get-ProjectCoverageModel -CoveragePath $root
        $model.Complete | Should -BeTrue
        $model.LineComplete | Should -BeTrue
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Not -Match "Coverage data is incomplete"
        $summary | Should -Not -Match "globally incomplete"
        $summary | Should -Match "50\.0%"
        $summary | Should -Match "uncovered objects"
    }

    Context "BC JSON streaming reader" {
        It "uses the runtime-appropriate reader without recursive conversion" {
            $path = Join-Path $fixtures "Line\CodeCoverage\line-app\coverage.bc.json"
            InModuleScope AnalyzeCodeCoverage -Parameters @{
                Path = $path
                Model = (New-StreamingReaderModel)
            } {
                Mock ConvertTo-CoverageHashtable {
                    throw "Recursive conversion must not be used for coverage reports."
                }
                $result = Read-BcCoverageReport -Path $Path -Model $Model `
                    -RequestedMode "line"
                $result.Valid | Should -BeTrue
                $result.Valid | Should -BeTrue
                $expectedReader = if ($PSVersionTable.PSVersion.Major -ge 7) {
                    "Newtonsoft.Json"
                }
                else {
                    "ConvertFrom-Json"
                }
                $result.Reader | Should -Be $expectedReader
                @($result.Data.Keys | Sort-Object) | Should -Be @(
                    "complete", "coverageMode", "diagnostics", "schemaVersion"
                )
                Should -Invoke ConvertTo-CoverageHashtable -Times 0 -Exactly
            }
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
            },
            @{
                Name = "invalid line"
                Json = '{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[{"objectType":5}]}'
                Expected = "*does not match schemaVersion*"
            },
            @{
                Name = "invalid line type"
                Json = '{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[],"methods":[],"lines":[{"objectType":true,"objectId":1,"lineNumber":1,"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"app/Code.al"}]}'
                Expected = "*does not match schemaVersion*"
            }
        ) {
            Param($Name, $Json, $Expected)

            $path = Join-Path $TestDrive "$Name.json"
            Set-Content -LiteralPath $path -Value $Json -Encoding UTF8
            $result = Read-BcCoverageReport -Path $path
            $result.Valid | Should -BeFalse
            $result.Reason | Should -BeLike $Expected
        }

        It "validates but does not materialize unused methods and procedure edges" {
            $path = Join-Path $TestDrive "unused-structures.json"
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":[],"tests":[],"procedureEdges":[{"unexpected":true}],"methods":[{"unexpected":true}],"lines":[]}
'@

            $result = Read-BcCoverageReport -Path $path

            $result.Valid | Should -BeTrue
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
            $result = Read-BcCoverageReport -Path $path
            $result.Valid | Should -BeFalse
            $result.Reason | Should -Match "does not match schemaVersion"
        }

        It "retains diagnostics and OR-unions duplicate line identities" {
            $path = Join-Path $TestDrive "duplicate-lines.json"
            Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
{
  "schemaVersion": "1.0",
  "coverageMode": "line",
  "complete": false,
  "diagnostics": ["Coverage method identity resolution failed for 'app'."],
  "sources": ["app/Code.al"],
  "tests": [],
  "procedureEdges": [],
  "methods": [],
  "lines": [
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":0,"status":0,"sourcePath":"app/Code.al"},
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"app/Code.al"}
  ]
}
'@
            $result = Read-BcCoverageReport -Path $path `
                -Model (New-StreamingReaderModel) -RequestedMode "line"

            $result.Valid | Should -BeTrue
            $result.Data.complete | Should -BeFalse
            $result.Data.diagnostics | Should -Be @(
                "Coverage method identity resolution failed for 'app'."
            )
            $result.ExtractedLineCount | Should -Be 2
            $result.AcceptedLineCount | Should -Be 1
            $facts = $result.Scope.ApplicationLines["app"]
            $facts.Count | Should -Be 1
            @($facts.Values)[0] | Should -BeTrue
        }

        It "streams a representative large-shaped report without recursive conversion" `
            -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
            $path = Join-Path $TestDrive "large-streaming.json"
            $writer = [System.IO.StreamWriter]::new(
                $path, $false, [System.Text.UTF8Encoding]::new($false), 65536)
            try {
                $writer.Write('{"schemaVersion":"1.0","coverageMode":"line","complete":true,"diagnostics":[],"sources":["app/Code.al"],"tests":[],"procedureEdges":[],"methods":[],"lines":[')
                foreach ($index in 1..50000) {
                    if ($index -gt 1) {
                        $writer.Write(',')
                    }
                    $writer.Write('{"objectType":5,"objectId":1,"lineNumber":')
                    $writer.Write($index)
                    $writer.Write(',"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"app/Code.al"}')
                }
                $writer.Write(']}')
            }
            finally {
                $writer.Dispose()
            }

            (Get-Item -LiteralPath $path).Length | Should -BeGreaterThan 5MB
            InModuleScope AnalyzeCodeCoverage -Parameters @{
                Path = $path
                Model = (New-StreamingReaderModel)
            } {
                Mock ConvertTo-CoverageHashtable {
                    throw "Recursive conversion must not be used for coverage reports."
                }
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $result = Read-BcCoverageReport -Path $Path -Model $Model `
                    -RequestedMode "line"
                $stopwatch.Stop()

                $result.Valid | Should -BeTrue
                $result.Reader | Should -Be "Newtonsoft.Json"
                $result.ExtractedLineCount | Should -Be 50000
                $result.AcceptedLineCount | Should -Be 50000
                $result.Scope.ApplicationLines["app"].Count | Should -Be 50000
                $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 30
                Should -Invoke ConvertTo-CoverageHashtable -Times 0 -Exactly
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
  "sources": ["app/Code.al"],
  "tests": [],
  "procedureEdges": [],
  "methods": [],
  "lines": [
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":0,"status":0,"sourcePath":"app/Code.al"},
    {"objectType":5,"objectId":1,"lineNumber":10,"lineType":3,"methodId":1,"hitCount":1,"status":1,"sourcePath":"app/Code.al"},
    {"objectType":5,"objectId":1,"lineNumber":11,"lineType":3,"methodId":1,"hitCount":0,"status":0,"sourcePath":"app/Code.al"}
  ]
}
'@
            $union = @{}
            $rootOrder = [System.Collections.Generic.List[string]]::new()

            $result = Read-BcCoverageReport -Path $reportPath -Model (New-StreamingReaderModel) `
                -RequestedMode "line" -SemanticLineUnion $union `
                -SemanticRootOrder $rootOrder

            $result.Valid | Should -BeTrue
            $result.Scope.ApplicationLines.Count | Should -Be 0
            $result.AcceptedLineCount | Should -Be 2
            $result.NewLineCount | Should -Be 2
            $union.Count | Should -Be 1
            $union["app"].Count | Should -Be 2
            $rootOrder | Should -Be @("app")
            @($union["app"].Values | Where-Object { $_ }).Count | Should -Be 1
        }
    }

    It "escapes report-derived Markdown and HTML and bounds values" {
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
        $model.Runs[0].AppName = $unsafe
        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Not -Match "<script>"
        $summary | Should -Match "&lt;script&gt;"

        $model.Lines = @{ "bad|<script>.al|5|1|10" = $false }
        { New-ProjectCoverageSummary $model } | Should -Not -Throw
        (New-ProjectCoverageSummary $model) | Should -Match "bad\\\|&lt;script&gt;"
        (New-ProjectCoverageSummary $model) | Should -Not -Match "bad\\\|&lt;script&gt;\.al"
    }

    It "bounds the entire UTF-8 summary below 900KB" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "Line")
        $apps = @()
        foreach ($index in 1..7000) {
            $apps += @{
                AppId = "$index"
                AppName = ("Long app $index " + ("x" * 150))
                RootIdentity = "src/$index"
                LineComplete = $false
                Lines = @{}
            }
        }
        $model.Apps = $apps
        $summary = New-ProjectCoverageSummary $model
        [System.Text.Encoding]::UTF8.GetByteCount($summary) | Should -BeLessOrEqual 921600
        $summary | Should -Match "Summary truncated"
    }

    It "keeps a missing expected repository artifact visible and hides repository union metrics" {
        $downloads = Join-Path $TestDrive "MissingExpected"
        New-Item -Path $downloads -ItemType Directory | Out-Null
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "ExpectedProject" -ProjectName "Expected project")
                )
            }) | ConvertTo-Json -Depth 10
        $model = Get-RepositoryCoverageModel -CoveragePath $downloads -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive
        $model.Complete | Should -BeFalse
        $model.Projects.Count | Should -Be 1
        $model.Apps.Count | Should -Be 0
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "Expected project"
        $summary | Should -Match "Coverage data is incomplete"
        $summary | Should -Not -Match "artifact is missing"
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
            -ProjectName "Depth one" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        $buildOrder = @(
            @{ buildDimensions = @((New-ExpectedDimension -Project "DepthOne" -ProjectName "Depth one")) },
            @{ buildDimensions = @((New-ExpectedDimension -Project "DepthTwo" -ProjectName "Depth two")) }
        ) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive

        $model.Complete | Should -BeFalse
        $model.Projects.Count | Should -Be 2
        @($model.Projects | Where-Object { $_.Project -eq "DepthTwo" })[0].Reasons |
            Should -Contain "Expected coverage artifact is missing."
    }

    It "unions cross-project facts instead of adding project totals" {
        $downloads = Join-Path $TestDrive "RepositoryUnion"
        $sourcePath = Join-Path $TestDrive "Shared\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-a" -Project "A" `
            -ProjectName "Project A" -BuildMode "Default" -SourcePath $sourcePath -HitCount 0 -MethodCovered $false
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-b" -Project "B" `
            -ProjectName "Project B" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "A" -ProjectName "Project A"),
                    (New-ExpectedDimension -Project "B" -ProjectName "Project B")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive
        $model.Complete | Should -BeTrue
        $model.Lines.Count | Should -Be 1
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "\*\*Line coverage:"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Match "Project A"
        $summary | Should -Match "Project B"
    }

    It "deduplicates the same repository line across build modes" {
        $downloads = Join-Path $TestDrive "BuildModeUnion"
        $sourcePath = Join-Path $TestDrive "Shared\BuildMode.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 0 -MethodCovered $false
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-clean" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Clean" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Default"),
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Clean")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive

        $model.Complete | Should -BeTrue
        $model.Projects.Count | Should -Be 2
        $model.Lines.Count | Should -Be 1
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $model.Apps.Count | Should -Be 1
        $model.Apps[0].LineComplete | Should -BeTrue
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
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-clean" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Clean" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
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
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive
        $summary = New-RepositoryCoverageSummary $model

        $model.Apps.Count | Should -Be 1
        $model.Apps[0].LineComplete | Should -BeFalse
        $summary | Should -Match "\| Tests \| Tests app \| unavailable \| unavailable \|"
        $summary | Should -Not -Match "\| Tests \| Tests app \| 1/1 \|"
    }

    It "marks known repository apps unavailable when a required dimension is missing" {
        $downloads = Join-Path $TestDrive "MissingApplicationDimension"
        $sourcePath = Join-Path $TestDrive "MissingDimension\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Default"),
                    (New-ExpectedDimension -Project "Tests" -ProjectName "Tests" -BuildMode "Clean")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive
        $summary = New-RepositoryCoverageSummary $model

        $model.Apps.Count | Should -Be 1
        $model.Apps[0].LineComplete | Should -BeFalse
        $summary | Should -Match "\| Tests \| Tests app \| unavailable \| unavailable \|"
    }

    It "does not calculate repository app coverage from a partial set of metadata-aware dimensions" {
        $downloads = Join-Path $TestDrive "OlderApplicationDimension"
        $sourcePath = Join-Path $TestDrive "OlderDimension\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-default" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-clean" -Project "Tests" `
            -ProjectName "Tests" -BuildMode "Clean" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
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
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive
        $summary = New-RepositoryCoverageSummary $model

        $model.Apps.Count | Should -Be 1
        $model.Apps[0].LineComplete | Should -BeFalse
        $summary | Should -Match "\| Tests \| Tests app \| unavailable \| unavailable \|"
    }

    It "sorts and escapes project application rows deterministically" {
        $model = Get-ProjectCoverageModel -CoveragePath (Join-Path $fixtures "All")
        $model.Apps = @(
            @{ AppName = "Zulu app"; AppId = "2"; RootIdentity = "z"; LineComplete = $false; Lines = @{} },
            @{ AppName = "A|<script> app"; AppId = "1"; RootIdentity = "a"; LineComplete = $false; Lines = @{} }
        )

        $summary = New-ProjectCoverageSummary $model

        $summary | Should -Match "(?s)### Application coverage.*A\\\|&lt;script&gt; app.*Zulu app"
        $summary | Should -Not -Match "<script>"
    }

    It "keeps duplicate regular app IDs at different roots as separate rows" {
        $projectModels = @(@{
                Project = "Apps"
                ProjectName = "Apps"
                Mode = "line"
                Runs = @(@{})
                Reasons = @()
                ApplicationMetadataAvailable = $true
                Apps = @(
                    @{
                        AppId = "duplicate"
                        AppName = "Localized app"
                        RootIdentity = "src/one"
                        LineComplete = $true
                        Lines = @{ "src/one/App.Codeunit.al|5|70000|10" = $true }
                    },
                    @{
                        AppId = "duplicate"
                        AppName = "Localized app"
                        RootIdentity = "src/two"
                        LineComplete = $true
                        Lines = @{ "src/two/App.Codeunit.al|5|70000|10" = $true }
                    }
                )
            })

        InModuleScope AnalyzeCodeCoverage -Parameters @{ ProjectModels = $projectModels } {
            param($ProjectModels)

            $applications = @(Get-RepositoryApplications -ProjectModels $ProjectModels)

            $applications.Count | Should -Be 2
            @($applications | ForEach-Object { $_.RootIdentity }) |
                Should -Be @("src/one", "src/two")
        }
    }

    It "uses the most-specific declared root for application attribution" {
        $details = @(
            @{ Identity = "src"; Path = "src"; Kind = "app" },
            @{ Identity = "src/tests"; Path = "src/tests"; Kind = "test" }
        )

        InModuleScope AnalyzeCodeCoverage -Parameters @{ Details = $details } {
            param($Details)

            $detail = Resolve-CoverageSourceRootDetail `
                -SourceIdentity "src/tests/Test.Codeunit.al" -SourceRootDetails $Details

            $detail.Kind | Should -Be "test"
            $detail.Path | Should -Be "src/tests"
        }
    }

    It "shows complete project rates but no repository metrics when another project is incomplete" {
        $downloads = Join-Path $TestDrive "MixedRepository"
        $sourcePath = Join-Path $TestDrive "Mixed\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-a" -Project "A" `
            -ProjectName "Project A" -BuildMode "Default" -SourcePath $sourcePath -HitCount 1 -MethodCovered $true
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "A" -ProjectName "Project A"),
                    (New-ExpectedDimension -Project "Missing" -ProjectName "Missing project")
                )
            }) | ConvertTo-Json -Depth 10
        $model = Get-RepositoryCoverageModel -CoveragePath $downloads -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive
        $summary = New-RepositoryCoverageSummary $model
        $model.Complete | Should -BeFalse
        $summary | Should -Match "Project A.*100.0%"
        $summary | Should -Match "Missing project"
        $summary | Should -Match "\*\*Line coverage:\*\* unavailable"
        $summary | Should -Not -Match "\*\*Line coverage:\*\* [0-9]"
        $summary | Should -Not -Match "Top 10 uncovered objects"
        $summary | Should -Not -Match "Per-test-app runs"
    }

    It "maps only source paths that resolve to existing repository files" {
        (Resolve-RepositoryCoverageSource -SourcePath "" -RepositoryRoot $TestDrive).Included | Should -BeFalse
        (Resolve-RepositoryCoverageSource -SourcePath "relative\File.al" -RepositoryRoot $TestDrive).Included | Should -BeFalse
        $outside = Join-Path (Split-Path $TestDrive -Parent) "outside\File.al"
        (Resolve-RepositoryCoverageSource -SourcePath $outside -RepositoryRoot $TestDrive).Included | Should -BeFalse
        $inside = Join-Path $TestDrive "inside\File.al"
        New-Item -Path (Split-Path $inside -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $inside -Value "codeunit 1 Inside { }" -Encoding UTF8
        $resolved = Resolve-RepositoryCoverageSource -SourcePath $inside `
            -RepositoryRoot $TestDrive -SourceRoots @("inside")
        $resolved.Included | Should -BeTrue
        $resolved.Identity | Should -Be "inside/file.al"
    }

    It "excludes and discloses external facts without showing empty percentages" {
        $repositoryRoot = Join-Path $TestDrive "Checkout"
        $downloads = Join-Path $TestDrive "ExternalDownloads"
        $sourcePath = Join-Path $TestDrive "External\External.Codeunit.al"
        New-Item -Path $repositoryRoot -ItemType Directory | Out-Null
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-external" -Project "ExternalProject" `
            -ProjectName "External project" -BuildMode "Default" -SourcePath $sourcePath `
            -HitCount 1 -MethodCovered $true
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "ExternalProject" -ProjectName "External project")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath $downloads `
            -BuildOrderJson $buildOrder -RepositoryRoot $repositoryRoot
        $summary = New-RepositoryCoverageSummary $model

        $model.Complete | Should -BeFalse
        $model.LineComplete | Should -BeFalse
        $model.Lines.Count | Should -Be 0
        $model.ExcludedLineFacts | Should -Be 1
        $summary | Should -Not -Match "Excluded coverage facts"
        $summary | Should -Match "unavailable"
        $summary | Should -Not -Match "\*\*Line coverage:\*\* 100\.0%"
        $summary | Should -Not -Match "Procedure coverage"
    }

    It "decodes unprefixed exporter paths only against the primary source root" {
        $parentFile = Join-Path $TestDrive "src\Thing.al"
        $nestedFile = Join-Path $TestDrive "src\App\Thing.al"
        foreach ($path in @($parentFile, $nestedFile)) {
            New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $path -Value "codeunit 1 Thing { }" -Encoding UTF8
        }

        $resolved = Resolve-RepositoryCoverageSource -SourcePath "Thing.al" `
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

        (Resolve-RepositoryCoverageSource -SourcePath "Primary.al" `
                -RepositoryRoot $TestDrive -SourceRoots $roots).Identity |
            Should -Be "src/primary/primary.al"
        (Resolve-RepositoryCoverageSource -SourcePath "external-1\app1\App.al" `
                -RepositoryRoot $TestDrive -SourceRoots $roots).Identity |
            Should -Be "src/app1/app.al"
        (Resolve-RepositoryCoverageSource -SourcePath "external-2\APP1.TEST\App.Test.al" `
                -RepositoryRoot $TestDrive -SourceRoots $roots).Identity |
            Should -Be "src/app1.test/app.test.al"

        foreach ($invalidSource in @(
                "external-3\missing\App.al",
                "external-1\wrong\App.al",
                "external-1\app1\Missing.al",
                "external-1\app1\..\Primary\Primary.al"
            )) {
            $invalid = Resolve-RepositoryCoverageSource -SourcePath $invalidSource `
                -RepositoryRoot $TestDrive -SourceRoots $roots
            $invalid.Included | Should -BeFalse
            $invalid.LocalMappingFailed | Should -BeTrue
        }
    }

    It "does not remap an unprefixed exporter path to a non-primary root" {
        foreach ($relativePath in @("Tests\Marker.al", "Actions\Marker.al")) {
            $path = Join-Path $TestDrive $relativePath
            New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $path -Value "codeunit 1 Marker { }" -Encoding UTF8
        }

        $resolved = Resolve-RepositoryCoverageSource -SourcePath "Actions\Marker.al" `
            -RepositoryRoot $TestDrive -SourceRoots @("Tests", "Actions")

        $resolved.Included | Should -BeFalse
        $resolved.LocalMappingFailed | Should -BeTrue
    }

    It "rejects coverage files reached through reparse points on Windows" -Skip:([System.IO.Path]::DirectorySeparatorChar -ne '\') {
        $repositoryRoot = Join-Path $TestDrive "Repository"
        $outsideRoot = Join-Path $TestDrive "Outside"
        $linkedRoot = Join-Path $repositoryRoot "Linked"
        New-Item -Path $repositoryRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $outsideRoot -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outsideRoot "Outside.al") `
            -Value "codeunit 1 Outside { }" -Encoding UTF8
        New-Item -Path $linkedRoot -ItemType Junction -Target $outsideRoot | Out-Null

        $resolved = Resolve-RepositoryCoverageSource -SourcePath "Outside.al" `
            -RepositoryRoot $repositoryRoot -SourceRoots @("Linked")

        $resolved.Included | Should -BeFalse
        $resolved.LocalMappingFailed | Should -BeTrue
    }

    It "keeps missing server line summaries unsafe in line mode" {
        $scope = @{
            IncludedLineObjects = @{}
            IncludedLineSources = @{}
            ExcludedLineObjects = @{ "1|308" = $true }
            ApplicationLines = @{}
            LineReasons = @()
            ExcludedLineFacts = 8
        }
        $report = @{
            coverageMode = "line"
            complete = $false
            diagnostics = @(
                "Coverage source root 'C:\repo\Empty' contains no AL source files.",
                "AL object 1:308 is defined by multiple source files and was not enriched.",
                "51 server coverage lines were not found in the supplied source.",
                "Coverage method identity resolution failed for 'C:\repo\App': compiler error"
            )
        }

        $assessment = Get-CoverageDiagnosticAssessment -Report $report -Scope $scope

        $assessment.LineGlobalUnsafe | Should -BeTrue
        @($assessment.LineReasons) | Should -Be @(
            "Server coverage lines could not be mapped to the supplied source."
        )
        @($assessment.LineAffectedSources).Count | Should -Be 0
        $assessment.Notices -join " " | Should -Match "global enrichment incomplete"
        $assessment.Notices -join " " | Should -Match "Ignored 3 diagnostics"
    }

    It "treats duplicate-object and method diagnostics as line-neutral in line mode" {
        $scope = @{
            IncludedLineObjects = @{ "1|308" = $true }
            IncludedLineSources = @{ "1|308" = @{ "src/app/source.al" = $true } }
            ExcludedLineObjects = @{}
            ApplicationLines = @{}
            LineReasons = @()
            ExcludedLineFacts = 0
        }
        $report = @{
            coverageMode = "line"
            complete = $false
            diagnostics = @(
                "AL object 1:308 is defined by multiple source files and was not enriched.",
                "Coverage method identity resolution failed for 'C:\repo\App': compiler error"
            )
        }

        $assessment = Get-CoverageDiagnosticAssessment -Report $report -Scope $scope

        $assessment.LineGlobalUnsafe | Should -BeFalse
        @($assessment.LineReasons).Count | Should -Be 0
        @($assessment.LineAffectedSources).Count | Should -Be 0
        $assessment.Notices -join " " | Should -Match "Ignored 2 diagnostics"
    }

    It "keeps duplicate-object and method diagnostics unsafe outside line mode" {
        $scope = @{
            IncludedLineObjects = @{}
            IncludedLineSources = @{}
            ExcludedLineObjects = @{ "1|308" = $true }
            ApplicationLines = @{}
            LineReasons = @()
            ExcludedLineFacts = 8
        }
        $report = @{
            coverageMode = "all"
            complete = $false
            diagnostics = @(
                "AL object 1:308 is defined by multiple source files and was not enriched.",
                "Coverage method identity resolution failed for 'C:\repo\App': compiler error"
            )
        }

        $assessment = Get-CoverageDiagnosticAssessment -Report $report -Scope $scope

        $assessment.LineGlobalUnsafe | Should -BeTrue
        @($assessment.LineReasons) | Should -Be @(
            "A duplicate AL object could not be uniquely enriched.",
            "Coverage method identity could not be resolved."
        )
    }

    It "keeps missing server lines globally unsafe without excluded facts" {
        $scope = @{
            IncludedLineObjects = @{}
            IncludedLineSources = @{}
            ExcludedLineObjects = @{}
            ApplicationLines = @{}
            LineReasons = @()
            ExcludedLineFacts = 0
        }
        $report = @{
            coverageMode = "line"
            complete = $false
            diagnostics = @(
                "4 server coverage lines were not found in the supplied source."
            )
        }

        $assessment = Get-CoverageDiagnosticAssessment -Report $report -Scope $scope

        $assessment.LineGlobalUnsafe | Should -BeTrue
        @($assessment.LineReasons) | Should -Be @(
            "Server coverage lines could not be mapped to the supplied source."
        )
    }

    It "admits repository-scoped lines from globally incomplete live-shaped reports" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $coveragePath = Join-Path $fixtureRoot "Artifact"
        $repositoryRoot = Join-Path $fixtureRoot "Repository"

        $model = Get-ProjectCoverageModel -CoveragePath $coveragePath -RepositoryRoot $repositoryRoot

        $model.Complete | Should -BeTrue
        $model.LineComplete | Should -BeTrue
        $model.Lines.Count | Should -Be 2
        $model.ExcludedLineFacts | Should -Be 2
        $lineMetrics = Get-CoverageMetrics $model.Lines
        $lineMetrics.Covered | Should -Be 1
        $lineMetrics.Total | Should -Be 2
        $model.Runs[0].LineComplete | Should -BeTrue
        $model.Runs[1].LineComplete | Should -BeTrue
        $model.Runs[0].ContainsKey("Lines") | Should -BeFalse
        $model.Runs[1].ContainsKey("Lines") | Should -BeFalse
        $model.Apps.Count | Should -Be 1
        $model.Apps[0].AppName | Should -Be "app1"
        $model.Apps[0].LineComplete | Should -BeTrue
        (Get-CoverageMetrics $model.Apps[0].Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $model.Apps[0].Lines).Total | Should -Be 2
        $model.Notices -join " " | Should -Match "global enrichment incomplete"
        $model.Notices -join " " | Should -Match "Ignored 4 diagnostics"

        $summary = New-ProjectCoverageSummary $model
        $summary | Should -Match "50\.0%"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Match "\| app1 \| 1/2 \| 50% \|"
        $summary | Should -Not -Match "\| App1\.abc\.Test \| [0-9]+/"
        $summary | Should -Not -Match "\| app1\.Test \| [0-9]+/"
        $summary | Should -Not -Match "Coverage data is incomplete"
        $summary | Should -Not -Match "Method identity resolution failed"
        $summary | Should -Not -Match "Ignored [0-9]+ diagnostics"
        $summary | Should -Not -Match "global enrichment incomplete"
        $summary | Should -Not -Match "\| Details \|"
        $summary | Should -Not -Match "project1/app1"
        $summary | Should -Not -Match "97\."
        $summary | Should -Not -Match "437/447"
    }

    It "retains each live-shaped run line rate before union" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        foreach ($case in @(
                @{ RunIndex = 0; Covered = 1 },
                @{ RunIndex = 1; Covered = 1 }
            )) {
            $root = Join-Path $TestDrive "Run$($case.RunIndex)"
            Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $root -Recurse
            $statusPath = Join-Path $root "CodeCoverage\coverage-status.json"
            $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $status.runs = @($status.runs[$case.RunIndex])
            $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath -Encoding UTF8

            $model = Get-ProjectCoverageModel -CoveragePath $root `
                -RepositoryRoot (Join-Path $fixtureRoot "Repository")
            $model.LineComplete | Should -BeTrue
            (Get-CoverageMetrics $model.Lines).Covered | Should -Be $case.Covered
            (Get-CoverageMetrics $model.Lines).Total | Should -Be 2
        }
    }

    It "attributes lines to the most-specific declared regular app and excludes test roots" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $root = Join-Path $TestDrive "TwoRegularApps"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $root -Recurse
        $statusPath = Join-Path $root "CodeCoverage\coverage-status.json"
        $status = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.sourceRootDetails[0].kind = "app"
        $status.sourceRootDetails[0].appName = "Alpha app"
        $status.sourceRootDetails[0].appId = "alpha-app"
        $status.sourceRootDetails[1].appName = "Beta app"
        $status.sourceRootDetails[1].appId = "beta-app"
        $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath -Encoding UTF8
        foreach ($reportPath in @(Get-ChildItem -LiteralPath $root -Filter "coverage.bc.json" -File -Recurse)) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.diagnostics = @("No source file was found for AL object 5:50000.")
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath.FullName -Encoding UTF8
        }

        $model = Get-ProjectCoverageModel -CoveragePath $root `
            -RepositoryRoot (Join-Path $fixtureRoot "Repository")

        $model.Apps.Count | Should -Be 2
        $alpha = @($model.Apps | Where-Object { $_.AppName -eq "Alpha app" })[0]
        $beta = @($model.Apps | Where-Object { $_.AppName -eq "Beta app" })[0]
        (Get-CoverageMetrics $alpha.Lines).Covered | Should -Be 3
        (Get-CoverageMetrics $alpha.Lines).Total | Should -Be 4
        (Get-CoverageMetrics $beta.Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $beta.Lines).Total | Should -Be 2
        $alpha.LineComplete | Should -BeFalse
        $beta.LineComplete | Should -BeTrue
        @($model.Apps | Where-Object { $_.AppName -eq "app1.Test" }).Count | Should -Be 0
    }

    It "scopes line diagnostics to regular apps without blocking them for test-root failures" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $repositoryRoot = Join-Path $fixtureRoot "Repository"
        $testFailureRoot = Join-Path $TestDrive "TestRootFailure"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $testFailureRoot -Recurse
        foreach ($reportPath in @(Get-ChildItem -LiteralPath $testFailureRoot -Filter "coverage.bc.json" -File -Recurse)) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.diagnostics = @("No source file was found for AL object 5:50000.")
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath.FullName -Encoding UTF8
        }

        $testFailure = Get-ProjectCoverageModel -CoveragePath $testFailureRoot `
            -RepositoryRoot $repositoryRoot
        $testFailure.LineComplete | Should -BeTrue
        $testFailure.Apps.Count | Should -Be 1
        $testFailure.Apps[0].LineComplete | Should -BeTrue
        (Get-CoverageMetrics $testFailure.Apps[0].Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $testFailure.Apps[0].Lines).Total | Should -Be 2

        $appFailureRoot = Join-Path $TestDrive "AppRootFailure"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $appFailureRoot -Recurse
        foreach ($reportPath in @(Get-ChildItem -LiteralPath $appFailureRoot -Filter "coverage.bc.json" -File -Recurse)) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.diagnostics = @("No source file was found for AL object 8:55000.")
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath.FullName -Encoding UTF8
        }

        $appFailure = Get-ProjectCoverageModel -CoveragePath $appFailureRoot `
            -RepositoryRoot $repositoryRoot
        $appFailure.Apps.Count | Should -Be 1
        $appFailure.Apps[0].LineComplete | Should -BeFalse
        (New-ProjectCoverageSummary $appFailure) |
            Should -Match "\| app1 \| unavailable \| unavailable \|"
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

        $model.Complete | Should -BeFalse
        $model.Apps.Count | Should -Be 0
        $summary | Should -Match "### Application coverage"
        $summary | Should -Match "No regular apps were available"
        $summary | Should -Not -Match "\| Line Tests \| [0-9]+/"
    }

    It "keeps diagnostic details and source paths out of project and repository Markdown" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $coveragePath = Join-Path $fixtureRoot "Artifact"
        $repositoryRoot = Join-Path $fixtureRoot "Repository"
        $diagnostic = "Coverage method identity resolution failed for 'Project1/app1': " +
            "Project1/app1/HelloWorld.al(5,45): error AL0247: target page is missing"

        $projectModel = Get-ProjectCoverageModel -CoveragePath $coveragePath `
            -RepositoryRoot $repositoryRoot
        $projectModel.Reasons += $diagnostic
        $projectModel.LineReasons += $diagnostic
        $projectModel.Notices += $diagnostic
        $projectModel.Runs[0].Reasons += $diagnostic
        $projectModel.Runs[0].LineReasons += $diagnostic
        $projectModel.Runs[0].Notices += $diagnostic
        $projectModel.Complete = $false
        $projectModel.LineComplete = $false
        $projectSummary = New-ProjectCoverageSummary $projectModel

        $projectSummary | Should -Match "Coverage data is incomplete"
        $projectSummary | Should -Match "action logs and raw CodeCoverage artifact"
        $projectSummary | Should -Not -Match ([regex]::Escape($diagnostic))
        $projectSummary | Should -Not -Match "AL0247"
        $projectSummary | Should -Not -Match "HelloWorld\.al"
        $projectSummary | Should -Not -Match "\| Details \|"
        $projectSummary | Should -Not -Match "\| Source \|"

        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Project1" -ProjectName "Project 1" -Mode "line")
                )
            }) | ConvertTo-Json -Depth 10
        $repositoryModel = Get-RepositoryCoverageModel -CoveragePath $coveragePath `
            -BuildOrderJson $buildOrder -RepositoryRoot $repositoryRoot
        $repositoryModel.Reasons += $diagnostic
        $repositoryModel.LineReasons += $diagnostic
        $repositoryModel.Notices += $diagnostic
        $repositoryModel.Projects[0].Reasons += $diagnostic
        $repositoryModel.Projects[0].LineReasons += $diagnostic
        $repositoryModel.Projects[0].Notices += $diagnostic
        $repositoryModel.Complete = $false
        $repositoryModel.LineComplete = $false
        $repositorySummary = New-RepositoryCoverageSummary $repositoryModel

        $repositorySummary | Should -Match "Coverage data is incomplete"
        $repositorySummary | Should -Match "action logs and raw CodeCoverage artifact"
        $repositorySummary | Should -Not -Match ([regex]::Escape($diagnostic))
        $repositorySummary | Should -Not -Match "AL0247"
        $repositorySummary | Should -Not -Match "HelloWorld\.al"
        $repositorySummary | Should -Not -Match "\| Details \|"
        $repositorySummary | Should -Not -Match "\| Source \|"
    }

    It "suppresses only the metric affected by safely classified diagnostics" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $repositoryRoot = Join-Path $fixtureRoot "Repository"

        $unknownRoot = Join-Path $TestDrive "UnknownDiagnostic"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $unknownRoot -Recurse
        foreach ($reportPath in @(Get-ChildItem -LiteralPath $unknownRoot -Filter "coverage.bc.json" -File -Recurse)) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.diagnostics = @("Coverage source enumeration failed for an unknown reason.")
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath.FullName -Encoding UTF8
        }
        $unknown = Get-ProjectCoverageModel -CoveragePath $unknownRoot -RepositoryRoot $repositoryRoot
        $unknown.LineComplete | Should -BeFalse
        $unknown.LineReasons -join " " | Should -Match "could not be safely scoped"

        $localRoot = Join-Path $TestDrive "LocalSourceDiagnostic"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $localRoot -Recurse
        foreach ($reportPath in @(Get-ChildItem -LiteralPath $localRoot -Filter "coverage.bc.json" -File -Recurse)) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.diagnostics = @("No source file was found for AL object 8:55000.")
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath.FullName -Encoding UTF8
        }
        $local = Get-ProjectCoverageModel -CoveragePath $localRoot -RepositoryRoot $repositoryRoot
        $local.LineComplete | Should -BeFalse
        $local.Apps[0].LineComplete | Should -BeFalse
    }

    It "ignores procedure-only method identity failures for regular-app line coverage" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $root = Join-Path $TestDrive "MissingMethodIdentity"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot "Artifact") -Destination $root -Recurse
        foreach ($reportPath in @(Get-ChildItem -LiteralPath $root -Filter "coverage.bc.json" -File -Recurse)) {
            $report = Get-Content -LiteralPath $reportPath.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.complete = $true
            $report.diagnostics = @()
            $report.methods[0].methodId = -1
            $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath.FullName -Encoding UTF8
        }

        $model = Get-ProjectCoverageModel -CoveragePath $root `
            -RepositoryRoot (Join-Path $fixtureRoot "Repository")

        $model.LineComplete | Should -BeTrue
        $model.Complete | Should -BeTrue
        (New-ProjectCoverageSummary $model) | Should -Not -Match "Procedure"
    }

    It "unions admitted incomplete reports for repository coverage" {
        $fixtureRoot = Join-Path $fixtures "ScopedIncomplete"
        $buildOrder = @(@{
                buildDimensions = @(
                    (New-ExpectedDimension -Project "Project1" -ProjectName "Project 1" -Mode "line")
                )
            }) | ConvertTo-Json -Depth 10

        $model = Get-RepositoryCoverageModel -CoveragePath (Join-Path $fixtureRoot "Artifact") `
            -BuildOrderJson $buildOrder -RepositoryRoot (Join-Path $fixtureRoot "Repository")

        $model.LineComplete | Should -BeTrue
        $model.Complete | Should -BeTrue
        $model.Lines.Count | Should -Be 2
        (Get-CoverageMetrics $model.Lines).Covered | Should -Be 1
        $model.Apps.Count | Should -Be 1
        $application = $model.Apps[0]
        $application.AppName | Should -Be "app1"
        $application.LineComplete | Should -BeTrue
        (Get-CoverageMetrics $application.Lines).Covered | Should -Be 1
        (Get-CoverageMetrics $application.Lines).Total | Should -Be 2
        $summary = New-RepositoryCoverageSummary $model
        $summary | Should -Match "50\.0%"
        $summary | Should -Not -Match "Procedure"
        $summary | Should -Match "\| Project 1 \| app1 \| 1/2 \| 50% \|"
        $summary | Should -Not -Match "\| Project 1 \| App1\.abc\.Test \|"
        $summary | Should -Not -Match "\| Project 1 \| app1\.Test \|"
        $summary | Should -Not -Match "Coverage data is incomplete"
        $summary | Should -Not -Match "Method identity resolution failed"
        $summary | Should -Not -Match "Ignored [0-9]+ diagnostics"
        $summary | Should -Not -Match "global enrichment incomplete"
        $summary | Should -Not -Match "\| Details \|"
        $summary | Should -Not -Match "project1/app1"
    }

    It "keeps duplicate app IDs in different projects as separate repository facts" {
        $downloads = Join-Path $TestDrive "DuplicateIds"
        $firstSource = Join-Path $TestDrive "W1\Shared.Codeunit.al"
        $secondSource = Join-Path $TestDrive "DK\Shared.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-w1" -Project "W1" `
            -ProjectName "W1" -BuildMode "Default" -SourcePath $firstSource -HitCount 1 -MethodCovered $true
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-dk" -Project "DK" `
            -ProjectName "DK" -BuildMode "Default" -SourcePath $secondSource -HitCount 1 -MethodCovered $true
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
            -BuildOrderJson $buildOrder -RepositoryRoot $TestDrive

        $model.Complete | Should -BeTrue
        $model.Lines.Count | Should -Be 2
        $model.Apps.Count | Should -Be 2
    }

    It "honors project summary settings" {
        (Test-CodeCoverageSummaryRequested -Settings @{ useSeparateTestAction = @{ codeCoverageSummary = "project" } } -Scope project) | Should -BeTrue
        (Test-CodeCoverageSummaryRequested -Settings @{ useSeparateTestAction = @{ codeCoverageSummary = "both" } } -Scope project) | Should -BeTrue
        (Test-CodeCoverageSummaryRequested -Settings @{ useSeparateTestAction = @{ codeCoverageSummary = "repository" } } -Scope project) | Should -BeFalse
    }

    It "declares the focused composite action contract" {
        $yaml = (Get-Content -LiteralPath $actionYamlPath -Raw -Encoding UTF8).Replace("`r", "")
        $yaml | Should -Match "(?ms)^  shell:.*?^    default: powershell$"
        $yaml | Should -Match "(?ms)^  scope:.*?^    required: true$"
        $yaml | Should -Match "(?ms)^  project:.*?^    default: '\.'$"
        $yaml | Should -Match "(?ms)^  coveragePath:.*?^    required: true$"
        $yaml | Should -Match "(?ms)^  buildOrderJson:.*?^    default: '\[\]'$"
        $yaml | Should -Match "using: composite"
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
            $analysisLog | Should -Match "Code coverage analysis detail:"
            $summary | Should -Match "Line coverage"
            $summary | Should -Not -Match "repository source path could not be validated"
        }
        finally {
            $env:GITHUB_WORKSPACE = $previousWorkspace
            $env:GITHUB_STEP_SUMMARY = $previousSummary
            $env:Settings = $previousSettings
        }
    }

    It "appends a repository summary from expected downloaded artifacts" {
        $downloads = Join-Path $TestDrive "ActionRepository"
        $sourcePath = Join-Path $TestDrive "Shared\Action.Codeunit.al"
        New-RepositoryArtifact -Root $downloads -ArtifactName "artifact-action" -Project "ActionProject" `
            -ProjectName "Action project" -BuildMode "Default" -SourcePath $sourcePath `
            -HitCount 1 -MethodCovered $true
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

    It "uses PowerShell 5 compatible syntax in the action and module" {
        foreach ($path in @($modulePath, $scriptPath)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }
}
