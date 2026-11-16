# Analyze Code Coverage

Creates a focused Markdown job summary from the compact coverage aggregate produced by the separate test action.

For the end-to-end collection, compaction, artifact, and analysis lifecycle, see [RunTests code coverage architecture](../RunTests/CodeCoverageArchitecture.md).

Project summaries are emitted only when `useSeparateTestAction.codeCoverageSummary` is `project` or `both`. Repository execution is expected to be workflow-gated and uses the expected build dimensions in `buildOrderJson`.

Summaries report executable-line coverage for authoritative regular `appFolders` only. Facts from `testFolders`, external Microsoft objects, and procedure enrichment do not contribute to visualization metrics or completeness.

Each app row and headline unions canonical line facts across all relevant test-app runs without double-counting. Coverage is complete only when every expected regular app is safely attributable and every required run and requested build dimension is available. Unknown or regular-app line inventory and mapping failures recorded during compaction make the affected app and aggregate unavailable.

The shared RunTests coverage coordinator remains the only writer of `coverage-status.json`. Built-in execution and coverage-aware `RunTestsInBcContainer.ps1` overrides contribute one AL-Go-owned run per selected test app. A missing or failed app run remains unsafe. RunTests validates source mappings in the checked-out build job, stores per-run assessments in status, and compacts the semantic line union into the versioned `coverage-aggregate.bin.gz` before artifact upload. The analyzer consumes only that status and aggregate contract. A missing, corrupt, or invalid aggregate fails closed.

## Inputs

| Name | Required | Description | Default |
| :-- | :-: | :-- | :-- |
| `shell` | No | PowerShell host used to render the summary. | `pwsh` |
| `scope` | Yes | Summary scope, `project` or `repository` | |
| `project` | No | Project folder | `.` |
| `coveragePath` | Yes | Path containing project coverage artifacts or separately downloaded repository artifacts | |
| `buildOrderJson` | No | Build order JSON containing expected repository `buildDimensions` across dependency depths | `[]` |

Repository source attribution uses the exact source-root order and application metadata validated and recorded by RunTests. Repository analysis does not check out or re-read source files.

## Outputs

None. The action can append a bounded summary to `GITHUB_STEP_SUMMARY`.
