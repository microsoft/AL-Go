[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Callback parameters match production signatures')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/CodeCoverageCoordinator.psm1' -Resolve) `
    -DisableNameChecking -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/RunTests/AlToolTestRunner.psm1' -Resolve) `
    -DisableNameChecking -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/AnalyzeCodeCoverage/AnalyzeCodeCoverage.psm1' -Resolve) `
    -DisableNameChecking -Force

Describe 'CodeCoverageCoordinator.psm1 Tests' {
    BeforeAll {
        Import-Module (
            Join-Path $PSScriptRoot '../Actions/RunTests/CodeCoverageCoordinator.psm1' -Resolve
        ) -DisableNameChecking -Force
        Import-Module (
            Join-Path $PSScriptRoot '../Actions/RunTests/AlToolTestRunner.psm1' -Resolve
        ) -DisableNameChecking

        function New-CoordinatorProject {
            Param([string] $name = "Project")

            $projectPath = Join-Path $TestDrive $name
            $appPath = Join-Path $projectPath "App"
            $testPath = Join-Path $projectPath "Test"
            New-Item -Path $appPath -ItemType Directory -Force | Out-Null
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null
            @{
                id = "11111111-1111-1111-1111-111111111111"
                name = "Regular App"
                idRanges = @(@{ from = 50100; to = 50149 })
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appPath "app.json") -Encoding UTF8
            @{
                id = "22222222-2222-2222-2222-222222222222"
                name = "Test App"
                idRanges = @(@{ from = 50150; to = 50199 })
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testPath "app.json") -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $appPath "App.al") `
                -Value "codeunit 50100 App { }" -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $testPath "Test.al") `
                -Value "codeunit 50101 Test { Subtype = Test; }" -Encoding UTF8
            return $projectPath
        }

        function New-CoordinatorSession {
            Param(
                [string] $projectPath,
                [string[]] $formats = @("bc-json"),
                [string] $platformVersion = "30.0.56026.0",
                [object[]] $testApps = @(),
                [hashtable] $settings = $null,
                [scriptblock] $analyzeRepo = $null
            )

            if (-not $settings) {
                $settings = @{
                    appFolders = @("App")
                    testFolders = @("Test")
                    useSeparateTestAction = @{
                        codeCoverageEnabled = $true
                        codeCoverageGenerateCobertura = "cobertura" -in $formats
                    }
                }
            }
            if ($testApps.Count -eq 0) {
                $testApps = @(
                    [PSCustomObject]@{
                        Id = "22222222-2222-2222-2222-222222222222"
                        Name = "Test App"
                        Path = Join-Path $projectPath "Test.app"
                    }
                )
            }
            $capability = Get-AlGoCodeCoverageCapability -platformVersion $platformVersion `
                -platformVersionReason ""
            return New-AlGoCodeCoverageSession -settings $settings -projectPath $projectPath `
                -baseFolder $projectPath -project "." -projectName "Project" -buildMode "Default" `
                -testApps $testApps -analyzeRepo $analyzeRepo `
                -capability $capability
        }

        function Get-CoordinatorRun {
            Param(
                [hashtable] $session,
                [string] $appId
            )

            return @($session.Runs | Where-Object { $_.AppId -eq $appId })[0]
        }

        function New-CoordinatorArtifactFixture {
            Param(
                [hashtable] $session,
                [hashtable] $run
            )

            return @{
                coverageOutputPath = $run.OutputPath
                formats = @($session.Formats)
                coverageIsComplete = $null
            }
        }

        function Get-CoordinatorStatusPath {
            Param([hashtable] $session)

            return Join-Path $session.RootPath "coverage-status.json"
        }

        function Write-CoordinatorCoverageArtifacts {
            Param(
                [hashtable] $context,
                [bool] $complete = $true,
                [string] $schemaVersion = "1.0",
                [string] $coverageMode = "line",
                [string[]] $diagnostics = @()
            )

            New-Item -Path $context.coverageOutputPath -ItemType Directory -Force | Out-Null
            if ("bc-json" -in @($context.formats)) {
                @{
                    schemaVersion = $schemaVersion
                    coverageMode = $coverageMode
                    complete = $complete
                    diagnostics = @($diagnostics)
                    sources = @()
                    tests = @()
                    procedureEdges = @()
                    methods = @()
                    lines = @()
                } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (
                    Join-Path $context.coverageOutputPath "coverage.bc.json"
                ) -Encoding UTF8
            }
            if ("cobertura" -in @($context.formats)) {
                Set-Content -LiteralPath (
                    Join-Path $context.coverageOutputPath "coverage.cobertura.xml"
                ) -Value "<coverage />" -Encoding UTF8
            }
            $context.coverageIsComplete = $complete
        }

    }

    BeforeEach {
        $script:originalRunnerDebug = $env:RUNNER_DEBUG
        $env:RUNNER_DEBUG = $null
    }

    AfterEach {
        $env:RUNNER_DEBUG = $script:originalRunnerDebug
    }

    It 'Creates one deterministic isolated run plan without publishing intermediate status' {
        $projectPath = New-CoordinatorProject
        $testApps = @(
            [PSCustomObject]@{
                Id = "22222222-2222-2222-2222-222222222222"
                Name = "Test App"
                Path = Join-Path $projectPath "Test.app"
            },
            [PSCustomObject]@{
                Id = "33333333-3333-3333-3333-333333333333"
                Name = "Other Test App"
                Path = Join-Path $projectPath "Other.Test.app"
            }
        )
        $session = New-CoordinatorSession -projectPath $projectPath -testApps $testApps

        $first = Get-CoordinatorRun -session $session -appId $testApps[0].Id
        $second = Get-CoordinatorRun -session $session -appId $testApps[1].Id

        $firstContext = New-CoordinatorArtifactFixture -session $session -run $first
        $secondContext = New-CoordinatorArtifactFixture -session $session -run $second
        $firstContext.coverageOutputPath | Should -Not -Be $secondContext.coverageOutputPath
        @($session.Keys | Sort-Object) | Should -Be @(
            "ApplicationIds",
            "ApplicationObjectIdRanges",
            "BuildMode",
            "Compactor",
            "Formats",
            "Project",
            "ProjectName",
            "PwshPath",
            "RepositoryRoot",
            "RootPath",
            "Runs",
            "SourceRootRecords",
            "Supported"
        )
        @($session.Runs).Count | Should -Be 2
        @($first.Keys | Sort-Object) |
            Should -Be @("AppId", "AppName", "OutputPath", "State")
        $first.OutputPath | Should -Be (
            Join-Path $session.RootPath "22222222-2222-2222-2222-222222222222"
        )
        $second.OutputPath | Should -Be (
            Join-Path $session.RootPath "33333333-3333-3333-3333-333333333333"
        )
        @($session.SourceRootRecords.Path) | Should -Be @(
            (Join-Path $projectPath "App"),
            (Join-Path $projectPath "Test")
        )
        $session.ApplicationIds | Should -Be @(
            "11111111-1111-1111-1111-111111111111"
        )
        $session.ApplicationObjectIdRanges.Count | Should -Be 1
        $session.ApplicationObjectIdRanges[0].From | Should -Be 50100
        $session.ApplicationObjectIdRanges[0].To | Should -Be 50149
        $first.State | Should -BeNullOrEmpty
        $second.State | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Get-CoordinatorStatusPath $session) | Should -BeFalse
    }

    It 'Uses the app-only AlTool root order when decoding a second application source' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $secondAppPath = Join-Path $projectPath "SecondApp"
        $secondTestPath = Join-Path $projectPath "SecondTest"
        New-Item -Path $secondAppPath -ItemType Directory -Force | Out-Null
        New-Item -Path $secondTestPath -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $secondAppPath "Second.al") `
            -Value "codeunit 50200 Second { }" -Encoding UTF8
        $session.SourceRootRecords = @(
            $session.SourceRootRecords[0],
            $session.SourceRootRecords[1],
            @{
                Path = $secondAppPath
                RelativePath = "SecondApp"
                Kind = "app"
                AppId = "33333333-3333-3333-3333-333333333333"
                AppName = "Second App"
            },
            @{
                Path = $secondTestPath
                RelativePath = "SecondTest"
                Kind = "test"
                AppId = "44444444-4444-4444-4444-444444444444"
                AppName = "Second Test"
            }
        )

        $result = InModuleScope CodeCoverageCoordinator -Parameters @{ Session = $session } {
            Mock Start-CodeCoverageAggregateWorker {
                Param(
                    $readerModulePath,
                    $repositoryRoot,
                    $metadata,
                    $temporaryPath,
                    $publishedPath,
                    $pwshPath
                )

                return @{ Metadata = $metadata }
            }

            $worker = Start-CodeCoverageCompactorInternal -session $Session
            $normalizedRoots = @(
                Get-NormalizedCoverageSourceRoots -RepositoryRoot $Session.RepositoryRoot `
                    -SourceRoots @($worker.Metadata.SourceRootDetails.path)
            )
            return @{
                Metadata = $worker.Metadata
                Resolved = Resolve-NormalizedRepositoryCoverageSource `
                    -SourcePath "external-1\SecondApp\Second.al" `
                    -RepositoryRoot $Session.RepositoryRoot -NormalizedRoots $normalizedRoots
            }
        }

        @($result.Metadata.SourceRootDetails.path) | Should -Be @("App", "SecondApp")
        @($result.Metadata.SourceRootDetails.kind) | Should -Be @("app", "app")
        $result.Resolved.Included | Should -BeTrue
        $result.Resolved.SourceRootIndex | Should -Be 1
        $result.Resolved.Identity | Should -Be "secondapp/second.al"
    }

    It 'Validates both formats and finalizes complete coverage' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath `
            -formats @("bc-json", "cobertura")
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context

        Complete-AlGoCodeCoverageRun -session $session -run $run `
            -coverageIsComplete $context.coverageIsComplete
        Complete-AlGoCodeCoverageSession -session $session

        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.runs[0].state | Should -Be "complete"
        $status.PSObject.Properties.Name | Should -Not -Contain "formats"
        $status.PSObject.Properties.Name | Should -Not -Contain "mode"
        $status.PSObject.Properties.Name | Should -Contain "aggregate"
        $status.aggregate | Should -Be "coverage-aggregate.bin.gz"
        $status.runs[0].diagnostics | Should -BeNullOrEmpty
        Test-Path -LiteralPath (
            Join-Path $context.coverageOutputPath "coverage.bc.json"
        ) | Should -BeFalse
    }

    It 'Treats external missing-source diagnostics as complete repository coverage' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context -complete $false `
            -diagnostics @("No source file was found for AL object 5:130002.")

        Complete-AlGoCodeCoverageRun -session $session -run $run `
            -coverageIsComplete $context.coverageIsComplete
        Complete-AlGoCodeCoverageSession -session $session

        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.runs[0].state | Should -Be "complete"
        $status.runs[0].diagnostics | Should -BeNullOrEmpty
    }


    It 'Admits a complete empty run while later app coverage determines project metrics' {
        $projectPath = New-CoordinatorProject
        $testApps = @(
            [PSCustomObject]@{
                Id = "22222222-2222-2222-2222-222222222222"
                Name = "Empty Test App"
                Path = Join-Path $projectPath "Empty.Test.app"
            },
            [PSCustomObject]@{
                Id = "33333333-3333-3333-3333-333333333333"
                Name = "Covered Test App"
                Path = Join-Path $projectPath "Covered.Test.app"
            }
        )
        $session = New-CoordinatorSession -projectPath $projectPath -testApps $testApps

        $emptyRun = Get-CoordinatorRun -session $session -appId $testApps[0].Id
        $emptyContext = New-CoordinatorArtifactFixture -session $session -run $emptyRun
        InModuleScope AlToolTestRunner -Parameters @{
            CoverageOutputPath = $emptyContext.coverageOutputPath
            CoverageFormats = $emptyContext.formats
        } {
            Write-EmptyAlToolCoverageArtifacts -CoverageOutputPath $CoverageOutputPath `
                -CoverageFormats $CoverageFormats
        }
        $emptyContext.coverageIsComplete = $true
        Complete-AlGoCodeCoverageRun -session $session -run $emptyRun `
            -coverageIsComplete $emptyContext.coverageIsComplete

        $sourcePath = Join-Path $projectPath "App\Coverage.al"
        Set-Content -LiteralPath $sourcePath -Value "codeunit 70000 Coverage { }" -Encoding UTF8
        $coveredRun = Get-CoordinatorRun -session $session -appId $testApps[1].Id
        $coveredContext = New-CoordinatorArtifactFixture -session $session -run $coveredRun
        New-Item -Path $coveredContext.coverageOutputPath -ItemType Directory -Force | Out-Null
        @{
            schemaVersion = "1.0"
            coverageMode = "line"
            complete = $true
            diagnostics = @()
            sources = @($sourcePath)
            tests = @()
            procedureEdges = @()
            methods = @()
            lines = @(@{
                    objectType = 5
                    objectId = 70000
                    lineNumber = 1
                    lineType = 3
                    methodId = 0
                    hitCount = 1
                    status = 1
                    sourcePath = $sourcePath
                })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (
            Join-Path $coveredContext.coverageOutputPath "coverage.bc.json"
        ) -Encoding UTF8
        $coveredContext.coverageIsComplete = $true
        Complete-AlGoCodeCoverageRun -session $session -run $coveredRun `
            -coverageIsComplete $coveredContext.coverageIsComplete
        Complete-AlGoCodeCoverageSession -session $session

        $model = Get-ProjectCoverageModel -CoveragePath $session.RootPath `
            -RepositoryRoot $projectPath

        $model.Reasons | Should -BeNullOrEmpty
        $model.Lines.Count | Should -Be 1
        $metrics = Get-CoverageMetrics $model.Lines
        $metrics.Covered | Should -Be 1
        $metrics.Total | Should -Be 1
    }

    It 'Accepts incomplete BC JSON coverage without generating Cobertura' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath -formats @("bc-json")
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context -complete $false

        Complete-AlGoCodeCoverageRun -session $session -run $run `
            -coverageIsComplete $context.coverageIsComplete
        Complete-AlGoCodeCoverageSession -session $session

        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.runs[0].state | Should -Be "incomplete"
        $status.PSObject.Properties.Name | Should -Not -Contain "formats"
    }

    It 'Fails closed when required artifacts are missing' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"

        {
            Complete-AlGoCodeCoverageRun -session $session -run $run `
                -coverageIsComplete $true
        } | Should -Throw "*expected 'bc-json' coverage artifact*"
        { Complete-AlGoCodeCoverageSession -session $session } |
            Should -Throw "*did not produce valid code coverage*"
    }

    It 'Lets the worker reject completeness that disagrees with BC JSON' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context -complete $false

        {
            Complete-AlGoCodeCoverageRun -session $session -run $run `
                -coverageIsComplete $true
        } | Should -Not -Throw
        { Complete-AlGoCodeCoverageSession -session $session } |
            Should -Throw "*completeness does not match the runner result*"
    }

    It 'Retains raw BC JSON after successful compaction when runner debug is enabled' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context
        $previousRunnerDebug = $env:RUNNER_DEBUG
        try {
            $env:RUNNER_DEBUG = "1"
            Complete-AlGoCodeCoverageRun -session $session -run $run `
                -coverageIsComplete $context.coverageIsComplete
            Complete-AlGoCodeCoverageSession -session $session
        }
        finally {
            $env:RUNNER_DEBUG = $previousRunnerDebug
        }

        Test-Path -LiteralPath (
            Join-Path $context.coverageOutputPath "coverage.bc.json"
        ) | Should -BeTrue
    }

    It 'Fails coverage and retains raw BC JSON when compaction fails (<Case>)' -TestCases @(
        @{ Case = "normally"; SuppressFailure = $false },
        @{ Case = "after an earlier runner failure"; SuppressFailure = $true }
    ) {
        Param($Case, $SuppressFailure)

        Mock -ModuleName CodeCoverageCoordinator Start-CodeCoverageCompactorInternal {
            return @{}
        }
        Mock -ModuleName CodeCoverageCoordinator Add-CodeCoverageAggregateWorkItem {}
        Mock -ModuleName CodeCoverageCoordinator Complete-CodeCoverageAggregateWorker {
            throw "worker failed"
        }
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context

        Complete-AlGoCodeCoverageRun -session $session -run $run `
            -coverageIsComplete $context.coverageIsComplete
        {
            Complete-AlGoCodeCoverageSession -session $session `
                -suppressFailure:$SuppressFailure
        } |
            Should -Throw "*Code coverage compaction failed*worker failed*"

        Test-Path -LiteralPath (
            Join-Path $context.coverageOutputPath "coverage.bc.json"
        ) | Should -BeTrue
        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.PSObject.Properties.Name | Should -Not -Contain "aggregate"
    }

    It 'Publishes worker diagnostics by app ID when reports complete out of order' {
        Mock -ModuleName CodeCoverageCoordinator Start-CodeCoverageCompactorInternal {
            return @{}
        }
        Mock -ModuleName CodeCoverageCoordinator Add-CodeCoverageAggregateWorkItem {}
        Mock -ModuleName CodeCoverageCoordinator Complete-CodeCoverageAggregateWorker {
            return @{
                LineCount = 0
                SizeBytes = 1
                TotalParseMilliseconds = 1
                RunDiagnostics = @{
                    "33333333-3333-3333-3333-333333333333" = @("Second diagnostic")
                    "22222222-2222-2222-2222-222222222222" = @("First diagnostic")
                }
                RunCompleteness = @{
                    "33333333-3333-3333-3333-333333333333" = $true
                    "22222222-2222-2222-2222-222222222222" = $true
                }
            }
        }
        $projectPath = New-CoordinatorProject
        $testApps = @(
            [PSCustomObject]@{
                Id = "22222222-2222-2222-2222-222222222222"
                Name = "First Test App"
                Path = Join-Path $projectPath "First.Test.app"
            },
            [PSCustomObject]@{
                Id = "33333333-3333-3333-3333-333333333333"
                Name = "Second Test App"
                Path = Join-Path $projectPath "Second.Test.app"
            }
        )
        $session = New-CoordinatorSession -projectPath $projectPath -testApps $testApps
        foreach ($run in @($session.Runs | Sort-Object AppId -Descending)) {
            $context = New-CoordinatorArtifactFixture -session $session -run $run
            Write-CoordinatorCoverageArtifacts -context $context
            Complete-AlGoCodeCoverageRun -session $session -run $run `
                -coverageIsComplete $context.coverageIsComplete
        }

        Complete-AlGoCodeCoverageSession -session $session

        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.runs[0].diagnostics | Should -Be @("First diagnostic")
        $status.runs[1].diagnostics | Should -Be @("Second diagnostic")
        $status.PSObject.Properties.Name | Should -Contain "aggregate"
    }

    It 'Retains failed-run raw coverage when a later compactor handoff fails' {
        $script:addWorkItemCalls = 0
        Mock -ModuleName CodeCoverageCoordinator Start-CodeCoverageCompactorInternal {
            return @{}
        }
        Mock -ModuleName CodeCoverageCoordinator Add-CodeCoverageAggregateWorkItem {
            $script:addWorkItemCalls++
            if ($script:addWorkItemCalls -eq 2) {
                throw "input failed"
            }
        }
        Mock -ModuleName CodeCoverageCoordinator Complete-CodeCoverageAggregateWorker {
            return @{
                LineCount = 0
                SizeBytes = 1
                TotalParseMilliseconds = 1
                RunDiagnostics = @{
                    "22222222-2222-2222-2222-222222222222" = @()
                }
                RunCompleteness = @{
                    "22222222-2222-2222-2222-222222222222" = $true
                }
            }
        }
        $projectPath = New-CoordinatorProject
        $testApps = @(
            [PSCustomObject]@{
                Id = "22222222-2222-2222-2222-222222222222"
                Name = "First Test App"
                Path = Join-Path $projectPath "First.Test.app"
            },
            [PSCustomObject]@{
                Id = "33333333-3333-3333-3333-333333333333"
                Name = "Second Test App"
                Path = Join-Path $projectPath "Second.Test.app"
            }
        )
        $session = New-CoordinatorSession -projectPath $projectPath -testApps $testApps
        $firstRun = $session.Runs[0]
        $secondRun = $session.Runs[1]
        $firstContext = New-CoordinatorArtifactFixture -session $session -run $firstRun
        $secondContext = New-CoordinatorArtifactFixture -session $session -run $secondRun
        Write-CoordinatorCoverageArtifacts -context $firstContext
        Write-CoordinatorCoverageArtifacts -context $secondContext

        Complete-AlGoCodeCoverageRun -session $session -run $firstRun `
            -coverageIsComplete $firstContext.coverageIsComplete
        {
            Complete-AlGoCodeCoverageRun -session $session -run $secondRun `
                -coverageIsComplete $secondContext.coverageIsComplete
        } | Should -Throw "*could not accept app*input failed*"
        Complete-AlGoCodeCoverageSession -session $session -suppressFailure

        Test-Path -LiteralPath (
            Join-Path $firstRun.OutputPath "coverage.bc.json"
        ) | Should -BeFalse
        Test-Path -LiteralPath (
            Join-Path $secondRun.OutputPath "coverage.bc.json"
        ) | Should -BeTrue
        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.aggregate | Should -Be "coverage-aggregate.bin.gz"
        @($status.runs.state) | Should -Be @("complete", "failed")
    }

    It 'Rejects unsupported schema versions and unexpected coverage modes' -TestCases @(
        @{ SchemaVersion = "2.0"; CoverageMode = "line"; ExpectedError = "*schemaVersion*" },
        @{ SchemaVersion = "1.0"; CoverageMode = "all"; ExpectedError = "*report mode*" }
    ) {
        Param($SchemaVersion, $CoverageMode, $ExpectedError)

        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"
        $context = New-CoordinatorArtifactFixture -session $session -run $run
        Write-CoordinatorCoverageArtifacts -context $context -schemaVersion $SchemaVersion `
            -coverageMode $CoverageMode

        {
            Complete-AlGoCodeCoverageRun -session $session -run $run `
                -coverageIsComplete $true
        } | Should -Not -Throw
        { Complete-AlGoCodeCoverageSession -session $session } |
            Should -Throw $ExpectedError
    }

    It 'Preserves unsupported runs without requiring artifacts' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath `
            -platformVersion "30.0.56025.999"
        $run = Get-CoordinatorRun -session $session `
            -appId "22222222-2222-2222-2222-222222222222"

        $session.Supported | Should -BeFalse
        $session.SourceRootRecords.Count | Should -Be 0
        { Complete-AlGoCodeCoverageRun -session $session -run $run } |
            Should -Not -Throw
        { Complete-AlGoCodeCoverageSession -session $session } | Should -Not -Throw
        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $status.runs[0].state | Should -Be "unsupported"
    }

    It 'Fails unresolved runs and publishes one final status' {
        $projectPath = New-CoordinatorProject
        $session = New-CoordinatorSession -projectPath $projectPath

        { Complete-AlGoCodeCoverageSession -session $session } |
            Should -Throw "*did not produce final code coverage*"
        $status = Get-Content -LiteralPath (Get-CoordinatorStatusPath $session) `
            -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $status.runs[0].state | Should -Be "failed"
    }

    It 'Preserves selected app IDs for contexts and output directories' {
        $projectPath = New-CoordinatorProject
        $testApps = @(
            [PSCustomObject]@{
                Id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
                Name = "Uppercase Test App"
                Path = Join-Path $projectPath "Uppercase.Test.app"
            }
        )

        $session = New-CoordinatorSession -projectPath $projectPath -testApps $testApps
        $run = Get-CoordinatorRun -session $session -appId $testApps[0].Id
        $context = New-CoordinatorArtifactFixture -session $session -run $run

        $run.AppId | Should -Be "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        Split-Path -Path $context.coverageOutputPath -Leaf |
            Should -Be "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    }

    It 'Resolves direct projectsToTest roots before creating run contexts' {
        $projectPath = New-CoordinatorProject
        $targetPath = Join-Path $projectPath "Target"
        $targetAppPath = Join-Path $targetPath "TargetApp"
        $targetTestPath = Join-Path $targetPath "TargetTest"
        New-Item -Path $targetAppPath -ItemType Directory -Force | Out-Null
        New-Item -Path $targetTestPath -ItemType Directory -Force | Out-Null
        @{
            id = "33333333-3333-3333-3333-333333333333"
            name = "Target App"
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetAppPath "app.json") -Encoding UTF8
        @{
            id = "44444444-4444-4444-4444-444444444444"
            name = "Target Tests"
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $targetTestPath "app.json") -Encoding UTF8
        New-Item -Path (Join-Path $targetPath ".AL-Go") -ItemType Directory -Force | Out-Null
        @{
            appFolders = @("TargetApp")
            testFolders = @("TargetTest")
        } | ConvertTo-Json | Set-Content -LiteralPath (
            Join-Path $targetPath ".AL-Go\settings.json"
        ) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $targetAppPath "TargetApp.al") `
            -Value "codeunit 50102 TargetApp { }" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $targetTestPath "TargetTest.al") `
            -Value "codeunit 50103 TargetTest { Subtype = Test; }" -Encoding UTF8
        $settings = @{
            appFolders = @("App")
            testFolders = @("Test")
            projectsToTest = @("Target")
            useSeparateTestAction = @{
                codeCoverageEnabled = $true
                codeCoverageGenerateCobertura = $false
            }
        }
        $analyzeRepo = {
            param($settings, $baseFolder, $project)
            $null = $baseFolder
            $null = $project
            return $settings
        }

        $session = New-CoordinatorSession -projectPath $projectPath -settings $settings `
            -analyzeRepo $analyzeRepo
        @($session.SourceRootRecords.AppName) | Should -Contain "Target App"
        @($session.SourceRootRecords.AppName) | Should -Contain "Target Tests"
    }

    It 'Rejects source roots outside the repository' {
        $projectPath = New-CoordinatorProject
        $outsidePath = Join-Path (Split-Path $projectPath -Parent) "Outside"
        New-Item -Path $outsidePath -ItemType Directory -Force | Out-Null
        $settings = @{
            appFolders = @("..\Outside")
            testFolders = @("Test")
            useSeparateTestAction = @{
                codeCoverageEnabled = $true
                codeCoverageGenerateCobertura = $false
            }
        }

        { New-CoordinatorSession -projectPath $projectPath -settings $settings } |
            Should -Throw "*outside the repository*"
    }
}
