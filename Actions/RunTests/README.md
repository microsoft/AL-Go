# Run tests

Run the normal tests (testFolders) for an AL-Go project against the build container created and kept alive by the RunPipeline action.

This action only does anything when the `useSeparateTestAction` setting is enabled. In that case, the RunPipeline action compiles, publishes and installs the apps, skips the normal tests and keeps the build container alive. This action then runs the normal tests against that same container and writes the results to `TestResults.xml` in the project folder.

Only normal tests (testFolders) are handled here. BCPT and page scripting tests continue to be executed by the RunPipeline action.

## Test runner

By default this action runs the tests through Microsoft's headless `al runtests` (AlTool) runner. It resolves the kept-alive container's connection settings (server, instance and developer-services port) from the container name, installs the AL developer tools as a `dotnet` global tool (`dotnet tool install Microsoft.Dynamics.BusinessCentral.Development.Tools --prerelease`), enumerates the test codeunits and runs them against the container, then writes the same `TestResults.xml` (JUnit) schema BcContainerHelper produces so downstream test result analysis is unchanged.

To run the tests through BcContainerHelper (or any other runner) instead, add a `RunTestsInBcContainer` override script under the project's `.AL-Go` folder. When present, it fully replaces the built-in AlTool runner and is called once per test app with the same parameters BcContainerHelper's `Run-TestsInBcContainer` expects.

### Known limitations

The built-in AlTool runner does not run `Legacy` test-type codeunits or tests that require UI or client-callback interaction. Repositories that rely on those should run their tests through BcContainerHelper by supplying a `RunTestsInBcContainer` override script (as described above), which fully replaces the AlTool runner.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| containerName | env.containerName is set by the RunPipeline action and identifies the container to run tests against (the container name is otherwise derived from the project) |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| project | | Project folder | '.' |
| installTestAppsJson | | Path to a JSON file containing a list of test apps to run tests in | '' |

## OUTPUT

None
