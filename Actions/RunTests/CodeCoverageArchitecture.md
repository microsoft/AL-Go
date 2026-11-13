# RunTests code coverage architecture

This document describes the developer-facing control flow, concurrency model, file contracts, and failure behavior for code coverage in the separate RunTests action.

The implementation deliberately separates four responsibilities:

1. RunTests selects test apps and invokes each app's tests.
1. AlTool runs tests and produces JUnit and coverage output.
1. The coverage coordinator validates each app's output and manages the coverage session.
1. A single background compactor streams valid BC JSON reports into one AL-Go aggregate for later analysis.

AnalyzeCodeCoverage runs after RunTests and artifact upload. It reads the final status and either consumes the aggregate or uses historical raw BC JSON reports.

## End-to-end workflow

```mermaid
flowchart TD
    RP[RunPipeline builds apps and keeps the container alive]
    RT[Run Tests workflow step]
    ENTRY[RunTests.ps1]
    ORCH[Invoke-AlGoTestRun]
    SESSION[New-AlGoCodeCoverageSession]
    LOOP[Sequential loop over selected test apps]
    TOOL[Invoke-AlToolTestRun or project override]
    AL[al runtests]
    COMPLETE[Complete-AlGoCodeCoverageRun]
    QUEUE[BlockingCollection queue]
    WORKER[One PowerShell 7 compactor runspace]
    FINAL[Complete-AlGoCodeCoverageSession]
    STATUS[coverage-status.json]
    AGG[coverage-aggregate.bin.gz]
    RAW[Per-app coverage.bc.json]
    COB[Per-app coverage.cobertura.xml]
    UPLOAD[Publish CodeCoverage artifact]
    PROJECT[AnalyzeCodeCoverage project scope]
    REPOJOB[AnalyzeCodeCoverage repository job]

    RP --> RT --> ENTRY --> ORCH
    ORCH --> SESSION --> LOOP
    LOOP --> TOOL --> AL --> COMPLETE
    COMPLETE -->|next app| LOOP
    COMPLETE -->|validated descriptor| QUEUE --> WORKER
    LOOP --> FINAL
    WORKER --> AGG
    FINAL --> STATUS
    FINAL -->|aggregate published and referenced| AGG
    FINAL -->|aggregate success deletes raw JSON| RAW
    FINAL -->|always retains requested Cobertura| COB
    STATUS --> UPLOAD
    AGG --> UPLOAD
    RAW -->|fallback only| UPLOAD
    COB --> UPLOAD
    UPLOAD --> PROJECT
    UPLOAD --> REPOJOB
```

The workflow uploads the CodeCoverage artifact before running the project summary. Repository summaries run in a separate job after the build jobs and download every matching CodeCoverage artifact.

## Detailed call sequence

```mermaid
sequenceDiagram
    participant Workflow as Build workflow
    participant Entry as RunTests.ps1
    participant RunTests as Invoke-AlGoTestRun
    participant Coordinator as Coverage coordinator
    participant Runner as AlTool runner or override
    participant AlTool as al runtests
    participant Queue as Work queue
    participant Worker as Compactor runspace
    participant Analyzer as AnalyzeCodeCoverage

    Workflow->>Entry: Run Tests step with pwsh
    Entry->>Entry: Read settings and AnalyzeRepo
    Entry->>RunTests: Invoke-AlGoTestRun
    RunTests->>RunTests: Get-TestAppsToRun
    RunTests->>Coordinator: Get-AlGoCodeCoverageCapability
    RunTests->>Coordinator: New-AlGoCodeCoverageSession
    Coordinator-->>RunTests: Ordered runs, roots, and session state

    loop One selected test app at a time
        RunTests->>Runner: Invoke tests for current app
        Runner->>AlTool: al runtests with JUnit and coverage arguments
        AlTool-->>Runner: Structured result and coverage files
        Runner-->>RunTests: Boolean test result and completeness
        RunTests->>Coordinator: Complete-AlGoCodeCoverageRun
        Coordinator->>Coordinator: Validate artifacts and BC JSON metadata
        alt First valid BC JSON report on PowerShell 7
            Coordinator->>Worker: Start-CodeCoverageAggregateWorker
        end
        Coordinator->>Queue: Add-CodeCoverageAggregateWorkItem
        Queue-->>Worker: Immutable report descriptor
        Note over RunTests,Worker: Parent starts the next app while the worker parses the previous report
        Worker->>Worker: Read-BcCoverageReport and merge semantic lines
        Worker-->>Coordinator: Telemetry event
    end

    RunTests->>Coordinator: Complete-AlGoCodeCoverageSession
    Coordinator->>Queue: CompleteAdding
    Coordinator->>Worker: Complete-CodeCoverageAggregateWorker
    Worker->>Worker: Write, checksum, validate, and atomically publish aggregate
    Worker-->>Coordinator: Aggregate descriptor
    Coordinator->>Coordinator: Write final coverage-status.json
    Coordinator->>Coordinator: Delete raw BC JSON only after status references aggregate
    Coordinator-->>RunTests: Finalized
    RunTests-->>Workflow: Test outcome and artifacts
    Workflow->>Workflow: Upload CodeCoverage artifact
    Workflow->>Analyzer: Analyze project coverage
    Analyzer->>Analyzer: Prefer aggregate, otherwise read historical raw reports
```

## Concurrency model

### Inside one RunTests action

- Test apps are producers and run sequentially in `Invoke-AlGoTestRun`. There is no parallel AlTool test execution within one project job.
- Compaction has exactly one consumer. `Start-CodeCoverageAggregateWorker` creates a separate PowerShell runspace with `PowerShell.BeginInvoke()`.
- The producer and consumer communicate through `BlockingCollection[object]`.
- The worker is started lazily after the first report passes artifact and metadata validation.
- Each subsequent valid report is enqueued as an immutable descriptor. The parent immediately proceeds to the next app.
- The worker parses one report at a time. There is no parser pool and no concurrent mutation of the semantic line union.
- `Complete-AlGoCodeCoverageSession` closes the queue and waits for the worker. This final drain is the only point where RunTests must wait for outstanding compaction.
- The parent is the only writer of `coverage-status.json`. The worker never writes status.

This design overlaps CPU and I/O-heavy report parsing with the next AlTool test run while avoiding locks around the aggregate model.

## Why RunTests compacts reports in parallel

### The repeated-data problem

Each selected test app is a separate AlTool invocation. AL-Go passes the same ordered source-root set to every invocation:

- App and test folders that contain AL source files from the current project.
- App and test folders that contain AL source files from direct `projectsToTest` projects.

The source roots let AlTool map runtime coverage facts back to repository files. They are intentionally project-scoped rather than test-app-scoped because a test can execute code across multiple applications and transitive platform dependencies.

Large projects can produce enough source-root and compiler-package arguments to exceed the Windows native command-line limit. `Invoke-AlRunTestsBatch` detects large argument sets, writes the arguments to a temporary UTF-8 AlTool response file, invokes `al runtests` with the single `@<file>` argument, and removes the file after the process exits. Connection credentials remain environment-based and are never written to the response file.

This means per-app BC JSON reports can contain large, overlapping executable-line inventories. A commonly used application can appear in many reports even though each invocation ran a different test app. In a repository such as BCApps, shared dependencies such as Base Application are exercised by many test apps, so the same semantic lines can be repeated across several very large reports.

Keeping every report until artifact upload and then parsing them in AnalyzeCodeCoverage has three costs:

1. The artifact contains repeated line data.
1. The analyzer must parse every large report after the tests have already finished.
1. The runner pays the full parsing latency at the end instead of overlapping it with useful test execution.

### Chosen design

RunTests starts one long-lived PowerShell 7 worker after the first report has passed metadata validation. Each completed app contributes an immutable descriptor to a `BlockingCollection`. The worker consumes descriptors in order and streams one report at a time while the parent starts the next test app.

The worker keeps one canonical executable-line union. Line identity is based on the resolved source and executable line identity, and duplicate facts use OR semantics: a line is covered if any run reports a positive hit count. Per-run completeness and diagnostic assessments remain separate so merging repeated lines does not erase whether an individual report was incomplete or unsafe.

After the producer closes the queue, the worker drains remaining reports and atomically publishes the aggregate. Raw BC JSON reports are deleted only after the aggregate has been written, validated, and referenced by the final status. If compaction fails, raw reports remain available to the historical analyzer path.

This design provides the following benefits:

- Each successful raw report receives one full semantic parse.
- Parsing can overlap the next app's AlTool execution.
- Repeated line data is collapsed before artifact upload.
- AnalyzeCodeCoverage reads the compact aggregate instead of reparsing all raw reports.
- One worker owns the union, so no parser pool, merge locks, or concurrent aggregate mutation are required.

The first implementation does not reduce peak runner disk usage because raw reports remain until durable aggregate publication. It reduces final waiting time and published artifact size while preserving a safe fallback.

### Alternative considered: test-app-specific source roots

An alternative was to determine which applications each test app can exercise and pass only those source roots to AlTool. That could reduce duplication when test apps have small, disjoint dependency graphs.

AL-Go does not use that approach because computing the exact runtime coverage boundary is difficult and error-prone:

- Dependencies are transitive and can differ from the directly declared test-app dependencies.
- Tests can call shared libraries, platform applications, and code reached through events or other indirect paths.
- Repository project relationships do not necessarily describe every application loaded in the test environment.
- An incomplete dependency calculation could omit valid coverage facts and create false confidence in the summary.
- In BCApps, many test apps depend directly or indirectly on Base Application and other common applications, so dependency-scoped roots would still include much of the same large source set and provide limited reduction.

Project-scoped roots plus semantic compaction favor correctness and deterministic source mapping. The compactor removes the resulting duplication without requiring AL-Go to predict the full runtime dependency graph or changing AlTool and platform behavior.

### Across workflow jobs

Build matrix jobs can run in parallel. Each project and build-mode job owns its own coverage directory, session, queue, and worker. No compactor is shared across jobs.

The repository AnalyzeCodeCoverage job starts after the build jobs. It downloads their artifacts and merges project models logically for the repository summary. It does not modify the uploaded artifacts.

## Function call map

| Function or step | Called by | When it runs | Responsibility |
| :-- | :-- | :-- | :-- |
| `RunTests.ps1` | RunTests composite action | Once per project build job | Reads settings, reconnects to the kept container, loads overrides, and calls the module orchestrator. |
| `Invoke-AlGoTestRun` | `RunTests.ps1` | Once per project build job | Selects apps, creates the coverage session, runs every app sequentially, finalizes coverage, preserves JUnit, and reports the test outcome. |
| `Get-TestAppsToRun` | `Invoke-AlGoTestRun` | Before session creation | Selects compiled test apps and optionally installed test apps. |
| `Get-AlGoCodeCoverageCapability` | `Invoke-AlGoTestRun` | Once when coverage is requested | Accepts coverage only for container platform 30.0.56026.0 or later. |
| `New-AlGoCodeCoverageSession` | `Invoke-AlGoTestRun` | Once before the app loop | Resolves ordered source roots and creates minimal ordered per-app run records. |
| `Resolve-CodeCoverageSourceRootData` | Session creation | Once for a supported session | Collects app and test roots containing AL source files from the project and direct `projectsToTest`, rejects unsafe paths, deduplicates, and sorts roots. |
| `Invoke-AlToolTestRun` | App loop or opted-in override | Once per selected test app | Enumerates tests, invokes AlTool, appends JUnit, surfaces diagnostics, and returns test success plus coverage completeness. |
| `Invoke-AlRunTestsBatch` | `Invoke-AlToolTestRun` | Once per app with test codeunits | Builds the `al runtests` arguments, uses a temporary response file when the native command would be too large, invokes the process, and parses its structured output. |
| `Complete-AlGoCodeCoverageRun` | App loop | Immediately after one supported invocation | Validates fixed artifacts and metadata, assigns the final run state, starts the worker if needed, and enqueues the report. |
| `Test-CodeCoverageArtifacts` | Per-run completion | Before enqueue | Checks requested files, schema version, mode, and agreement between structured completeness and BC JSON. |
| `Start-CodeCoverageAggregateWorker` | Per-run completion | Lazily for the first valid BC JSON report | Creates the queue, event queue, and single background PowerShell runspace. |
| `Add-CodeCoverageAggregateWorkItem` | Per-run completion | Once per valid complete or incomplete report | Adds sequence, app identity, state, completeness, and raw report path to the queue. |
| `Invoke-CodeCoverageAggregateWorker` | Background runspace | Until the queue is closed | Streams reports, evaluates diagnostics, and maintains the canonical OR-covered semantic line union. |
| `Complete-AlGoCodeCoverageSession` | `Invoke-AlGoTestRun` | Once after the app loop, including error paths | Resolves unfinished states, drains compaction, writes final status, performs safe cleanup, and enforces coverage failures. |
| `Complete-CodeCoverageAggregateWorker` | Session completion | During final drain | Closes the queue, waits for the runspace, returns the validated aggregate descriptor, and disposes worker resources. |
| `Write-CodeCoverageStatusInternal` | Session completion | Once, with one fallback rewrite only if aggregate referencing fails | Atomically publishes the final status. There are no intermediate status writes. |
| `AnalyzeCodeCoverage.ps1` | Project step or repository job | After coverage artifact publication | Loads settings, builds the requested model, logs details, and appends Markdown to the job summary. |
| `Get-ProjectCoverageModelFromStatus` | Analyzer | Once per status file | Validates status and aggregate contracts, or reads raw reports when no aggregate descriptor exists. |
| `Get-RepositoryCoverageModel` | Repository analyzer | Once after artifact download | Checks expected build dimensions and combines project application models without double-counting semantic lines. |

## Per-app runner paths

### Built-in runner

`Invoke-AlToolTestRun` performs these steps:

1. Set the container username and password only in process environment variables.
1. Enumerate enabled test codeunits through BcContainerHelper and apply `testType` and disabled-test filtering.
1. Create empty valid JUnit and coverage artifacts when the app has zero test codeunits.
1. Resolve the container connection and company.
1. Call `Invoke-AlRunTestsBatch`.
1. Append test results to the shared project `TestResults.xml`.
1. Return a Boolean test result.
1. Remove credential environment variables in `finally`.

When coverage is supported, `Invoke-AlRunTestsBatch` adds:

```text
--coverage line
--coverage-output <per-app-directory>
--coverage-format <format>
--coverage-source-root <ordered-root>
```

The format and source-root flags are repeated for every configured value.

An AlTool exit code of 1 can represent failed tests. Valid coverage and JUnit data are still processed. Unexpected native failures, invalid structured output, or missing requested coverage output throw.

### Project override

A coverage-aware `.AL-Go/RunTestsInBcContainer.ps1` receives:

- Historical test parameters in `$parameters`.
- Coverage-only values in the same hashtable when coverage is supported.

The coverage values are `codeCoverageFormats`, `codeCoverageSourceRoots`, `codeCoverageOutputPath`, `codeCoverageAlToolModulePath`, `codeCoverageAlToolPath`, and `codeCoverageIsComplete`. The formats always include `bc-json`; `cobertura` is included when `codeCoverageGenerateCobertura` is true. The override runs once per app and must return a Boolean test result. For supported coverage it must write coverage into `codeCoverageOutputPath` and set `codeCoverageIsComplete`. AL-Go retains ownership of artifact validation, run state, compaction, and status publication.

When coverage is disabled or unsupported, AL-Go omits the coverage values and the override runs with the historical parameter shape.

## Coverage session lifecycle

### 1. Capability

Coverage is requested only when `useSeparateTestAction.codeCoverageEnabled` is true. The container platform handoff must parse as version 30.0.56026.0 or later.

If the platform is missing, malformed, or older:

- A warning explains the requirement.
- Tests continue without coverage arguments.
- The final status records each selected app as `unsupported`.

### 2. Session construction

The session contains:

- Project identity and build mode.
- Requested formats. Executable-line mode is a module constant.
- Ordered repository-relative source roots and source-root details.
- One minimal ordered run record per app.
- The canonical coverage root from which per-app, status, and aggregate paths are derived.
- The repository root needed by the streaming reader.
- Optional live PowerShell 7 worker state.

Source-root order is deterministic. It is part of the report mapping contract and the aggregate fingerprint.

RunTests derives each app's output path from the session root and app ID. Built-in execution reads session-wide formats and source roots directly. A custom override receives the same values as temporary `codeCoverage*` entries in its existing parameter hashtable and reports completeness through `codeCoverageIsComplete`. These invocation values are not retained in the per-app run record.

### 3. Per-app completion

After each runner invocation, the coordinator validates:

- The runner supplied a Boolean completeness value.
- Every requested fixed artifact exists.
- BC JSON is a valid complete document.
- `schemaVersion` is `1.0`.
- Report mode is `line`.
- Structured and file completeness agree.

The run becomes `complete`, `incomplete`, or `failed`. Test pass or failure is independent from coverage completeness, so a failed test app can still contribute valid coverage.

### 4. Background compaction

For every queued report, the worker:

1. Streams the report with `Read-BcCoverageReport`.
1. Validates the full JSON document and required schema.
1. Discards unused test, method, procedure-edge, and source payload after validation.
1. Resolves executable lines to the ordered source roots.
1. Evaluates diagnostic effects for included and excluded sources.
1. Merges lines by canonical semantic identity.

Duplicate line facts use OR semantics: a semantic line is covered when any duplicate has a positive hit count.
Duplicate-object and method-identity enrichment diagnostics are notices because they do not remove an otherwise exported executable line. A server missing-line summary remains globally unsafe because its omitted lines have no structured source identities that AL-Go can validate.

The worker retains only:

- Global aggregate metadata.
- Per-run diagnostic assessments.
- The semantic executable-line union.
- Ordering and telemetry needed for deterministic output.

### 5. Final publication

The worker writes the aggregate to a unique temporary path, calculates its SHA-256, validates the temporary file and source-root fingerprint, and atomically moves it to `coverage-aggregate.bin.gz`.

The parent then:

1. Verifies that the aggregate contains every valid run.
1. Writes one final `coverage-status.json` through a temporary file and atomic move.
1. Deletes per-app `coverage.bc.json` only after status durably references the aggregate.
1. Retains per-app Cobertura output.
1. Reports session and overlap telemetry.

## On-disk contracts

Successful PowerShell 7 compaction normally leaves:

```text
.buildartifacts/CodeCoverage/
|-- coverage-status.json
|-- coverage-aggregate.bin.gz
|-- <test-app-guid>/
|   `-- coverage.cobertura.xml
`-- <another-test-app-guid>/
    `-- coverage.cobertura.xml
```

Fallback or Windows PowerShell 5.1 execution leaves raw reports:

```text
.buildartifacts/CodeCoverage/
|-- coverage-status.json
|-- <test-app-guid>/
|   |-- coverage.bc.json
|   `-- coverage.cobertura.xml
`-- <another-test-app-guid>/
    |-- coverage.bc.json
    `-- coverage.cobertura.xml
```

`coverage-status.json` contains project metadata, ordered source roots, final run states, and an optional aggregate descriptor. The descriptor includes the format, contract version, relative path, checksum, source-root fingerprint, run count, line count, and size.

The aggregate is an AL-Go contract, not an AlTool schema 1.0 document. It contains the data required to reproduce existing project and repository line summaries without reparsing raw reports.

## Analyzer selection and validation

`Get-ProjectCoverageModelFromStatus` treats the status as authoritative:

- If status has no aggregate descriptor, it reads per-run `coverage.bc.json`. This preserves historical artifacts and the compaction fallback.
- If status has an aggregate descriptor, it validates the descriptor, path containment, checksum, source-root fingerprint, header metadata, run identities, counts, and size.
- A declared but missing, corrupt, or mismatched aggregate fails closed. The analyzer does not silently fall back to raw reports after an aggregate was published.

Only regular application roots contribute to rates and uncovered-object tables. The aggregate preserves the diagnostic assessment and excluded-fact accounting for test roots and external objects, but those facts do not affect application percentages.

Repository analysis verifies the expected project and build-mode dimensions from `buildOrderJson`, then unions canonical lines across valid project models.

## Failure and cleanup rules

| Condition | Test execution | Coverage result | Raw BC JSON |
| :-- | :-- | :-- | :-- |
| Coverage disabled | Unchanged | No session or status | Not created |
| Unsupported platform | Runs normally | Final `unsupported` states and warning | Not created |
| Test assertions fail but coverage is valid | Test result remains failed or warning per settings | Valid report is compacted and analyzed | Deleted after aggregate publication |
| Supported coverage output is missing or invalid | Fails closed | Run becomes `failed` and its output is not authoritative | Retained when the session uses raw fallback; otherwise subject to normal post-publication cleanup |
| Worker enqueue or parse fails | Continues to finalization | Warning and historical raw-report fallback | Retained |
| Aggregate validation or publication fails | Continues with raw fallback unless another coverage failure exists | Status has no aggregate descriptor | Retained |
| Status cannot reference a valid aggregate | Aggregate publication is removed and status is rewritten for raw fallback | Raw path remains authoritative | Retained |
| Aggregate succeeds but raw deletion fails | Warning | Aggregate remains authoritative | Undeleted files may also be uploaded |
| Earlier runner exception exists | Original exception wins | Best available final status is written with suppressed secondary failure | Retained as needed |

## Telemetry

Per-report compactor logs include:

- App ID and report bytes.
- Queue wait and queue depth.
- Parse duration.
- Extracted, accepted, new, and aggregate line counts.
- Process private memory before and after parsing.

Session completion logs include:

- Run and line counts.
- Total active parse time.
- Final drain time.
- Aggregate size.
- Removed raw bytes.
- Number of reports whose parsing overlapped another app's test execution.

No report content or credentials are logged.

## Change checklist

When changing this flow:

1. Keep test app execution and test-result semantics independent from coverage completeness.
1. Keep the parent as the only status writer.
1. Do not delete raw reports before aggregate publication, validation, and durable status reference.
1. Preserve deterministic source-root, run, and semantic-line ordering.
1. Keep aggregate and historical raw analyzer paths equivalent.
1. Test complete, incomplete, failed-test-valid-coverage, zero-codeunit, duplicate-line, diagnostics, multi-run, and repository cases.
1. Test worker startup, queue drain, worker failure, corruption, fingerprint mismatch, atomic publication, cleanup, and fallback.
1. Run RunTests and analyzer suites in PowerShell 7 and supported consumer tests in Windows PowerShell 5.1.

The primary implementation and tests are:

- `Actions/RunTests/RunTests.psm1`
- `Actions/RunTests/CodeCoverageCoordinator.psm1`
- `Actions/RunTests/AlToolTestRunner.psm1`
- `Actions/.Modules/CodeCoverageAggregate.psm1`
- `Actions/.Modules/CodeCoverageAggregateFormat.psm1`
- `Actions/.Modules/CodeCoverageReportReader.psm1`
- `Actions/AnalyzeCodeCoverage/AnalyzeCodeCoverage.psm1`
- `Tests/RunTests.Test.ps1`
- `Tests/CodeCoverageCoordinator.Test.ps1`
- `Tests/CodeCoverageAggregate.Test.ps1`
- `Tests/AnalyzeCodeCoverage.Test.ps1`
