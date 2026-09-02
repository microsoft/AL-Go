# Run tests

Run normal tests (`testFolders`) against the build container kept alive by the RunPipeline action.

Enable this action with the `useSeparateTestAction` setting. It is used when normal tests are enabled and RunPipeline creates one local build container. Builds with `additionalCountries` or without a local build container continue to run normal tests in RunPipeline. BCPT and page scripting tests always remain in RunPipeline.

The action keeps `TestResults.xml` in the project folder for AnalyzeTests and copies a produced result to `.buildartifacts/TestResults.xml` for artifact upload. It does not create a result artifact when no result is produced. After the run, it refreshes `ContainerEventLog.evtx` in the project folder so failure diagnostics include test-time events.

Compiled apps are selected by matching their app IDs to `testFolders`, which excludes BCPT-only apps from the shared test-app artifact. When `runTestsInAllInstalledTestApps` is enabled, apps from `installTestAppsJson` are also included. The action honors `disabledTests.json` files found recursively under the matching test folder and project-wide `<appId>.disabledTests.json` files for both the default runner and overrides.

## Test runner

By default, AlTool runs enabled normal tests for each app through one batch and connection while BcContainerHelper provides app metadata, container configuration, company discovery, and server-side test enumeration. The optional `testType` setting limits enumeration to `UnitTest`, `IntegrationTest`, or `Uncategorized`; blank runs all test types. The action writes JUnit output compatible with AL-Go AnalyzeTests and downstream processing.

To use another test runner, add a `RunTestsInBcContainer` override script under the project's `.AL-Go` folder. The override replaces AlTool execution and receives the standard BcContainerHelper test parameters once per test app, including a configured `testType`. Custom overrides may interpret additional values such as `Legacy`.

### Known limitations

The built-in AlTool execution path does not run `Legacy` test-type codeunits or tests that require UI or client-callback interaction. Repositories that rely on those should execute their tests through BcContainerHelper by supplying a `RunTestsInBcContainer` override script as described above.

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
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| token | | The GitHub token running the action and exposed to test override scripts | github.token |
| project | | Project folder | '.' |
| installTestAppsJson | | Path to a JSON file containing a list of test apps to run tests in | '' |

## OUTPUT

None
