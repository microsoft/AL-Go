# Run tests

Run the normal tests (testFolders) for an AL-Go project against the build container created and kept alive by the RunPipeline action.

This action runs when the `useSeparateTestAction` setting is enabled and RunPipeline can keep a single local build container alive. RunPipeline compiles, publishes and installs the apps, skips the normal tests and keeps the container alive. This action then runs the normal tests against that same container and writes the results to `TestResults.xml` in the project folder. That root file remains available to AnalyzeTests and is also copied to `.buildartifacts/TestResults.xml` for artifact upload. If test execution produces no result file, no artifact result is created. Builds with `additionalCountries` continue to run normal tests inside RunPipeline so every country is tested.

Only normal tests (testFolders) are handled here. BCPT and page scripting tests continue to be executed by the RunPipeline action.

Compiled apps are selected from `.buildartifacts/TestApps` by matching their app IDs to the source `app.json` files in `testFolders`. BCPT apps share the same artifact folder but are not selected unless their app ID is also configured as a normal test app. When `runTestsInAllInstalledTestApps` is enabled, apps listed in `installTestAppsJson` are added independently of `testFolders`.

For each normal test app, the action honors `disabledTests.json` files found recursively under its source test folder and `<appId>.disabledTests.json` files found recursively under the AL-Go project folder. These exclusions are passed to both the built-in AlTool runner and `RunTestsInBcContainer` overrides.

## Test runner

By default this action executes tests through Microsoft's headless `al runtests` (AlTool) runner. BcContainerHelper remains in use for app metadata, container configuration, company discovery, and test enumeration. The action installs the AL developer tools as a `dotnet` global tool (`dotnet tool install Microsoft.Dynamics.BusinessCentral.Development.Tools --prerelease`), then AlTool executes each enumerated test codeunit in its own `al runtests <codeunitId>` invocation. The action writes JUnit output compatible with AL-Go AnalyzeTests and downstream processing.

To replace AlTool test execution with BcContainerHelper (or another runner), add a `RunTestsInBcContainer` override script under the project's `.AL-Go` folder. When present, it replaces the built-in AlTool execution path and is called once per test app with the same parameters BcContainerHelper's `Run-TestsInBcContainer` expects.

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
