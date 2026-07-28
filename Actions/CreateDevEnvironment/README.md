# Create Dev Environment

**PREVIEW** — part of the modular build (`useModularBuild`).

Create a Business Central development container, install dependency apps and the test toolkit. This is phase 1 of the modular build (CreateDevEnvironment → PublishApps → RunTests). Requires `useCompilerFolder = true`.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with secrets needed for the container (licenseFileUrl, keyVault* etc.) must be read by a prior call to the ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| token | | The GitHub token running the action | github.token |
| artifact | | ArtifactUrl to use for the build | '' |
| project | | Project folder | '.' |
| buildMode | | Specifies a mode to use for the build steps | Default |
| installAppsJson | | A path to a JSON-formatted list of apps to install | '' |
| installTestAppsJson | | A path to a JSON-formatted list of test apps to install | '' |

## OUTPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| containerName | The name of the development container that was created |

The action also persists a small pipeline context file in `RUNNER_TEMP`, consumed by the PublishApps and RunTests actions in the same job.
