# Separate test code coverage architecture

This document describes the final code coverage flow for the separate `RunTests` action.
The implementation collects executable-line coverage, compacts all selected test-app runs into one
project artifact, and renders project or repository summaries from that compact artifact.

## Activation and capability

Coverage is controlled by the flat `useSeparateTestAction` object:

- `codeCoverageEnabled` enables collection.
- `codeCoverageGenerateCobertura` adds a Cobertura interoperability file. BC JSON is always requested
  because it is the input to AL-Go analysis.
- `codeCoverageSummary` selects `none`, `project`, `repository`, or `both`.

Collection is supported only when:

- The kept-alive Business Central container reports platform version `30.0.56026.0` or later.
- A PowerShell 7 `pwsh` executable is available for the coverage worker.

RunPipeline reads the actual container platform version after a successful build and passes it to
RunTests. Missing, malformed, old, or unavailable capability information produces a GitHub warning
and tests continue without coverage. Once capability is confirmed, collection and compaction errors
are real failures and do not trigger a noncoverage retry.

## Session flow

RunTests performs these steps once for each project:

1. Resolve existing AL source roots from the current project and direct `projectsToTest` projects.
1. Create `.buildartifacts/CodeCoverage`.
1. Start one persistent `pwsh -NoProfile -NonInteractive` worker.
1. Run each selected test app sequentially.
1. Write each app's fixed AlTool files to a stable, app-specific directory.
1. Send the app ID, completeness state, and completed BC JSON report path to the worker through
   redirected standard input.
1. Close worker input, wait for compaction, and publish final status.

Per-app directories prevent AlTool's fixed filenames from overwriting earlier reports:

```text
.buildartifacts/
  CodeCoverage/
    <app-id>/
      coverage.bc.json
      coverage.cobertura.xml
    coverage-aggregate.bin.gz
    coverage-status.json
```

Cobertura files exist only when requested. Raw BC JSON files are deleted after successful compaction
unless `RUNNER_DEBUG=1`. They are retained when compaction fails.

## Runner integration

The built-in runner invokes AlTool once per selected test app with:

- `--coverage line`
- The app-specific `--coverage-output` directory.
- `--coverage-format bc-json`.
- Optional `--coverage-format cobertura`.
- Every resolved regular application `--coverage-source-root`.

Large argument sets use a temporary UTF-8 response file. It contains no credentials and is deleted
after the AlTool invocation.

An existing `.AL-Go/RunTestsInBcContainer.ps1` override keeps its historical single-hashtable
signature. When coverage is supported, AL-Go adds:

- `codeCoverageOutputPath`
- `codeCoverageFormats`
- `codeCoverageSourceRoots`
- `codeCoverageApplicationIds`
- `codeCoverageAlToolModulePath`
- `codeCoverageAlToolPath`
- `codeCoverageIsComplete`

The override must use the provided output directory, return its historical Boolean test result, and
set `codeCoverageIsComplete` to a Boolean. It should use its existing noncoverage behavior when
`codeCoverageOutputPath` is absent.

`Invoke-AlToolTestRun` also supports optional `CoverageAppPaths` for compatible preview AlTool builds
that require compiler-instrumented packages. AL-Go does not populate this parameter in the built-in
path.

## Worker and reader

`CodeCoverageAggregateWorker.ps1` is a small child-process entry point. It imports the shared
streaming reader, accepts one JSON descriptor per input line, and keeps the semantic line union in
the child process.

The reader:

- Requires BC JSON schema `1.0` and line mode.
- Requires the report completeness value to be Boolean.
- Validates source attribution against source roots recorded by RunTests.
- Rejects ambiguous duplicate roots and invalid source mappings.
- Builds a semantic key from source identity, object type, object ID, and line number.
- OR-unions covered state so a line covered by any test-app run is covered in the final project
  result.
- Retains AlTool diagnostics as unclassified strings for later warnings.

The worker is the sole owner of structured coverage diagnostics and returns them keyed by app ID,
so completion order does not affect run attribution. The runner emits only top-level AlTool
warnings.

Keeping parsing and the union in the child avoids loading multi-gigabyte reports in the PowerShell 5
parent process and avoids parsing every report twice.

## Published contracts

### `coverage-aggregate.bin.gz`

The aggregate is a gzip-compressed binary stream containing:

- The versioned `ALGOCOV1` magic header.
- One declared semantic line count.
- Root identity, semantic line key, and covered state for every retained line.

The writer publishes to a temporary file and moves it to the fixed filename only after successful
completion. Readers validate successful decompression, the header, records, and declared count.
There is no raw-report analyzer fallback.

### `coverage-status.json`

The coordinator is the only status writer. Status records:

- Project identity and source-root attribution.
- One final entry for each selected test app.
- Per-run state and raw AlTool diagnostics.
- The fixed aggregate filename only after successful compaction.

Status is also written through a temporary file and moved into place.

## Failure behavior

Test outcome and coverage completeness are independent:

- Failed tests may still produce valid coverage and are included in the aggregate.
- A test failure remains a test failure even when coverage succeeds.
- Missing or invalid expected coverage files fail coverage.
- Worker, reader, or aggregate publication failures fail coverage and retain raw BC JSON.
- If tests and coverage both fail, the test failure remains primary and the coverage failure is
  emitted as an additional GitHub error.

Coverage is not downgraded after capability has been confirmed.

## Analysis and workflow fan-in

`AnalyzeCodeCoverage` consumes only `coverage-status.json` and
`coverage-aggregate.bin.gz`.

Project summaries are rendered from the project's artifact when requested. Repository analysis
downloads the expected project artifacts, uses build dimensions marked with
`codeCoverageRepositorySummary`, and unions semantic line facts across projects without
double-counting.

Only regular application roots from `appFolders` contribute to percentages and uncovered-object
lists or are passed to AlTool as coverage source roots. Test roots and external sources remain
excluded. The compactor suppresses only AlTool's exact missing-source diagnostic for object IDs
outside every regular repository application's declared `idRanges`. If these external diagnostics
fully explain an incomplete report, the run is treated as complete. Repository-owned missing
sources and all other diagnostics remain visible. Available line facts always contribute to
metrics, including facts from genuinely incomplete reports. The summary lists globally incomplete
runs and distinct remaining AlTool diagnostics as warnings.

Coverage is unavailable only for hard failures such as a missing or failed run, unreadable status,
missing or invalid aggregate, or an expected repository dimension without a matching artifact.

Repository analyzer jobs depend on all expanded build jobs. They do not check out the repository
because source attribution was already validated during compaction in the checked-out build job.

## Main implementation files

- `Actions/RunTests/RunTests.psm1`
- `Actions/RunTests/CodeCoverageCoordinator.psm1`
- `Actions/RunTests/CodeCoverageAggregateWorker.ps1`
- `Actions/RunTests/AlToolTestRunner.psm1`
- `Actions/.Modules/CodeCoverageReportReader.psm1`
- `Actions/.Modules/CodeCoverageAggregateFormat.psm1`
- `Actions/AnalyzeCodeCoverage/AnalyzeCodeCoverage.psm1`
