# Run tests

Run normal tests from `testFolders` against an existing Business Central container.

For the developer-facing call sequence, worker lifecycle, file contracts, and failure behavior, see [RunTests code coverage architecture](CodeCoverageArchitecture.md).

Enable this action with `useSeparateTestAction.enabled`. It is used when normal tests are enabled and RunPipeline creates one local build container. Builds with `additionalCountries` or without a local build container continue to run normal tests in RunPipeline. BCPT and page scripting tests always remain in RunPipeline.

The action reads analyzed settings from `Settings` and reconnects to the kept-alive build container using `containerName` and `containerCredential`; `project` selects the project folder, and `installTestAppsJson` supplies installed test-app paths from earlier jobs.

Compiled apps are matched to normal `testFolders`; eligible installed test apps are added from `installTestAppsJson`, and matching disabled-test files are applied. The built-in runner uses AlTool and BcContainerHelper metadata to execute each selected app and append JUnit results to `TestResults.xml`.

Produced results remain in the project folder for AnalyzeTests and are copied to `.buildartifacts/TestResults.xml`. The action refreshes `ContainerEventLog.evtx` after execution.

## Test runner

By default, AlTool runs enabled normal tests for each app through one batch and connection while BcContainerHelper provides app metadata, container configuration, company discovery, and server-side test enumeration. The optional `useSeparateTestAction.testType` value limits enumeration to `UnitTest`, `IntegrationTest`, or `Uncategorized`; blank runs all test types. The action writes JUnit output compatible with AL-Go AnalyzeTests and downstream processing.

To use another test runner, add `RunTestsInBcContainer.ps1` under the project's `.AL-Go` folder. The override keeps the historical signature, runs once per test app, receives the standard BcContainerHelper test parameters including `testType`, and returns a Boolean test result. Custom overrides may interpret additional test types such as `Legacy`.

```powershell
param([hashtable] $parameters)
```

When coverage is disabled or the container does not support coverage, AL-Go does not add coverage parameters or request coverage output and retains the historical per-app invocation behavior. When coverage is supported, AL-Go adds `codeCoverageMode`, ordered `codeCoverageFormats`, absolute ordered `codeCoverageSourceRoots`, sorted `codeCoverageApplicationIds` for regular app roots, the allocated `codeCoverageOutputPath`, `codeCoverageAlToolModulePath`, `codeCoverageAlToolPath`, and a mutable `codeCoverageIsComplete` output to the existing `$parameters` hashtable. AL-Go resolves current-project and direct `projectsToTest` roots centrally while its `AnalyzeRepo` callback is in scope. Repository overrides must not reconstruct or receive that callback. Credentials remain only in the historical parameter fields and must not be serialized into artifacts or diagnostics.

For supported coverage, indicated by the presence of `codeCoverageOutputPath`, the override imports `codeCoverageAlToolModulePath`, invokes `Invoke-AlToolTestRun` once for the current app with the supplied coverage values, and copies the runner's completeness output into `codeCoverageIsComplete`:

```powershell
if ($parameters.ContainsKey('codeCoverageOutputPath')) {
    Import-Module $parameters.codeCoverageAlToolModulePath -Force -DisableNameChecking
    $coverageIsComplete = $null
    $passed = Invoke-AlToolTestRun `
        -ContainerName $parameters.containerName `
        -Credential $parameters.credential `
        -ExtensionId $parameters.extensionId `
        -AppName $parameters.appName `
        -CompanyName $parameters.companyName `
        -Tenant 'default' `
        -TestType $parameters.testType `
        -DisabledTests $parameters.disabledTests `
        -AlToolPath $parameters.codeCoverageAlToolPath `
        -JUnitResultFileName $parameters.JUnitResultFileName `
        -CoverageMode $parameters.codeCoverageMode `
        -CoverageOutputPath $parameters.codeCoverageOutputPath `
        -CoverageFormats $parameters.codeCoverageFormats `
        -CoverageSourceRoots $parameters.codeCoverageSourceRoots `
        -CoverageIsComplete ([ref] $coverageIsComplete)
    $parameters.codeCoverageIsComplete = $coverageIsComplete
    return [bool]$passed
}
```

The override should use its existing noncoverage implementation when `codeCoverageOutputPath` is absent. After every supported invocation, AL-Go validates completeness, path containment, fixed artifacts, and BC JSON schema/mode data. Missing or invalid output fails closed. AL-Go alone updates and finalizes `coverage-status.json`. The override continues to return the historical Boolean test result, and failed tests may retain valid coverage.

`Invoke-AlToolTestRun` also accepts optional `CoverageAppPaths` for compatible AlTool builds that use compiler-instrumented app packages as their executable-line inventory. AL-Go does not populate this parameter by default. An override opting into package mode must map `codeCoverageApplicationIds` to exactly one package from the same build and server revision for each regular source-root app, then pass those paths explicitly. Omitting `CoverageAppPaths` preserves source enrichment behavior.

When the combined AlTool arguments are large, the runner writes them to a temporary UTF-8 response file and passes that file to `al runtests`. This avoids the Windows native command-line limit for projects with many source roots and compiler-instrumented packages. The response file contains no credentials and is removed immediately after the invocation.

## Code coverage

Set `useSeparateTestAction.codeCoverageEnabled` to `true` to collect coverage with the built-in AlTool runner or an opted-in `RunTestsInBcContainer.ps1` override. AL-Go installs the latest prerelease of `Microsoft.Dynamics.BusinessCentral.Development.Tools` when AlTool is needed. Coverage requires container platform 30.0.56026.0 or later. After RunPipeline creates the container, it hands the actual platform version to RunTests. Missing, malformed, older, or failed version detection produces a warning and tests continue normally without coverage. Once the platform requirement is confirmed, collection or export errors fail the run instead of silently retrying without coverage.

AL-Go collects executable-line coverage. Procedure coverage is not currently exposed because AlTool source enrichment cannot reliably construct a local method inventory in the separate-test environment. `codeCoverageFormats` accepts `bc-json` and `cobertura` and defaults to both. `codeCoverageSummary` accepts `none`, `project`, `repository`, or `both` and defaults to `both`; `none` disables visualization without disabling raw collection. Project and repository summaries require `bc-json`, so use `codeCoverageSummary: none` for Cobertura-only collection. Existing app and test folders that contain AL source files in the current AL-Go project are passed automatically as source roots to improve source mapping. Test projects also use the analyzed app and test folders from their direct `projectsToTest` targets.

RunTests writes one final `coverage-status.json` after every selected app has reached a final state and aggregate publication has either succeeded or safely fallen back to raw reports. Repository-relative source-root identities let repository summaries map raw report paths consistently across build jobs. Ordered source-root details classify each root as an app or test folder and include available app identity from `app.json`. These details are action-level attribution data and are not repeated per test-app run or in the override parameters.

Each built-in or override test-app run initially writes to `.buildartifacts/CodeCoverage/<app-id>/` with the fixed `coverage.bc.json` and `coverage.cobertura.xml` names. On PowerShell 7, one background worker per coverage session streams validated BC JSON reports while later test apps run, preserving the semantic executable-line union and per-run diagnostic assessment needed by AL-Go summaries. After all queued reports have been parsed, AL-Go atomically publishes the versioned `coverage-aggregate.bin.gz`, references it from `coverage-status.json`, and deletes the raw per-app BC JSON files. Per-app Cobertura files remain available for external tooling.

If compaction fails, AL-Go publishes no aggregate descriptor and retains every raw BC JSON report. The project and repository analyzers remain compatible with historical raw artifacts and use them as the safe fallback when no aggregate was published. A published aggregate is checksum and source-root fingerprint validated and is treated fail closed if it is missing, corrupt, or mismatched. Failed tests may still contribute valid coverage; an execution or artifact failure remains a failed coverage run. PowerShell 7 performs background compaction. Windows PowerShell 5.1 retains raw BC JSON reports for sequential fallback analysis.

Project and repository summaries include only regular applications declared through `appFolders`. Lines from `testFolders` and external Microsoft objects remain in raw artifacts but are excluded from rates, uncovered-object lists, and completeness. Multiple test apps and repeated build dimensions contribute to one semantic line union per regular app.
Duplicate-object and method-identity enrichment diagnostics do not invalidate line coverage by themselves. A server missing-line summary still makes line coverage incomplete because AlTool does not provide structured identities that AL-Go can safely scope to included or excluded sources.

### Known limitations

The built-in AlTool execution path does not run `Legacy` test-type codeunits or tests that require UI or client-callback interaction. Repositories that rely on those can retain the original override and optionally adopt the coverage context contract for supported execution buckets.

The current live E2E environment does not guarantee container platform 30.0.56026.0 or later. Automated tests therefore cover older and unavailable platform-version handoffs; live coverage collection awaits a deterministic BC30-capable E2E environment.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| containerName | env.containerName is set by the RunPipeline action and identifies the container to run tests against (the container name is otherwise derived from the project) |
| containerCredential | env.containerCredential is set by the RunPipeline action and contains the masked, base64-encoded JSON credential used to reconnect to the kept-alive container |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | pwsh |
| token | | The GitHub token running the action and exposed to test override scripts | github.token |
| project | | Project folder | '.' |
| installTestAppsJson | | Path to a JSON file containing a list of test apps to run tests in | '' |

## OUTPUT

None
