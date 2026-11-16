# Analyze Code Coverage

Creates a focused Markdown job summary from the compact coverage aggregate produced by the separate test action.

For the end-to-end collection, compaction, artifact, and analysis lifecycle, see [RunTests code coverage architecture](../RunTests/CodeCoverageArchitecture.md).

Project summaries are emitted only when `useSeparateTestAction.codeCoverageSummary` is `project` or `both`. Repository execution is expected to be workflow-gated and uses the expected build dimensions in `buildOrderJson`.

Summaries report executable-line coverage for authoritative regular `appFolders` only. Facts from `testFolders`, external Microsoft objects, and procedure enrichment do not contribute to visualization metrics.

Each app row and headline unions canonical line facts across all relevant test-app runs without double-counting. Available line facts always contribute to metrics, including facts from globally incomplete reports. Summaries show globally incomplete runs and distinct AlTool diagnostics as warnings.

The shared RunTests coverage coordinator remains the only writer of `coverage-status.json`. Built-in execution and coverage-aware `RunTestsInBcContainer.ps1` overrides contribute one AL-Go-owned run per selected test app. A PowerShell 7 child process validates source mappings in the checked-out build job, stores raw per-run diagnostics in status, and compacts the semantic line union into the versioned `coverage-aggregate.bin.gz` before artifact upload. The analyzer consumes only that status and aggregate contract. Coverage is unavailable for hard failures such as a missing or failed run, unreadable status, missing or invalid aggregate, or an expected repository dimension without a matching artifact.

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
