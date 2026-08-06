# Run tests

Run the normal tests (testFolders) for an AL-Go project against the build container created and kept alive by the RunPipeline action.

This action only does anything when the `useSeparateTestAction` setting is enabled. In that case, the RunPipeline action compiles, publishes and installs the apps, skips the normal tests and keeps the build container alive. This action then runs the normal tests against that same container and writes the results to `TestResults.xml` in the project folder.

Only normal tests (testFolders) are handled here. BCPT and page scripting tests continue to be executed by the RunPipeline action.

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
