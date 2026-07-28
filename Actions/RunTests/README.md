# Run Tests

**PREVIEW** — part of the modular build (`useModularBuild`).

Run the tests, BCPT tests and page scripting tests in the development container created by CreateDevEnvironment and populated by PublishApps. This is phase 3 of the modular build (CreateDevEnvironment → PublishApps → RunTests). Requires `useCompilerFolder = true`.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets must be read by a prior call to the ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| token | | The GitHub token running the action | github.token |
| project | | Project folder | '.' |
| buildMode | | Specifies a mode to use for the build steps | Default |

## OUTPUT

None

Test results are written to `TestResults.xml` / `bcptTestResults.json` in the project folder. The action reads the pipeline context persisted by CreateDevEnvironment to reuse the container and its credential.
