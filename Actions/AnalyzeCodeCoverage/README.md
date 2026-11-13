# Analyze Code Coverage

Creates a focused Markdown job summary from Business Central JSON coverage reports produced by the separate test action. Raw coverage artifacts are read without modification.

For the end-to-end collection, compaction, artifact, and analysis lifecycle, see [RunTests code coverage architecture](../RunTests/CodeCoverageArchitecture.md).

Project summaries are emitted only when `useSeparateTestAction.codeCoverageSummary` is `project` or `both`. Repository execution is expected to be workflow-gated and uses the expected build dimensions in `buildOrderJson`.

Summaries report executable-line coverage for authoritative regular `appFolders` only. Raw facts from `testFolders`, external Microsoft objects, and procedure enrichment remain in the artifacts and logs but do not contribute to visualization metrics or completeness.

Each app row and headline unions canonical line facts across all relevant test-app runs without double-counting. Coverage is complete only when every expected regular app is safely attributable and every required run and build dimension is available. A globally incomplete BC JSON report can still be complete for AL-Go when incompleteness affects only excluded external objects, test roots, or procedure enrichment. Unknown or regular-app line inventory and mapping failures make the affected app and aggregate unavailable. Older artifacts without ordered source-root classification remain parseable but do not render application metrics.

The shared RunTests coverage coordinator remains the only writer of `coverage-status.json`. Built-in execution and coverage-aware `RunTestsInBcContainer.ps1` overrides contribute one AL-Go-owned run per selected test app. A missing or failed app run remains unsafe. On PowerShell 7, RunTests compacts the validated reports into one checksum-protected, source-root-bound `coverage-aggregate.bin.gz` before artifact upload. The analyzer prefers that versioned AL-Go aggregate and does not reparse deleted raw reports. Historical statuses without an aggregate descriptor continue to use the per-run BC JSON path. A published but missing, corrupt, or mismatched aggregate fails closed rather than silently falling back.

## Inputs

| Name | Required | Description | Default |
| :-- | :-: | :-- | :-- |
| `shell` | No | PowerShell host. Use `pwsh` for streaming large BC JSON reports. | `pwsh` |
| `scope` | Yes | Summary scope, `project` or `repository` | |
| `project` | No | Project folder | `.` |
| `coveragePath` | Yes | Path containing project coverage artifacts or separately downloaded repository artifacts | |
| `buildOrderJson` | No | Build order JSON containing expected repository `buildDimensions` across dependency depths | `[]` |

Repository source attribution uses the exact source-root order recorded by RunTests. The primary root receives unprefixed exporter paths, while `external-N` paths resolve only against root index `N`. Absolute legacy paths use most-specific root matching. Every included path must resolve to an existing file within both its declared regular-app root and the repository.

## Outputs

None. The action can append a bounded summary to `GITHUB_STEP_SUMMARY`.
