# Build and Test AL-Go project

**PREVIEW** — the modular-build orchestrator, selected by the `useModularBuild` setting.

Compiles the apps and test apps, creates a development environment (Business Central container), signs the apps (optionally), publishes them and runs the tests — then removes the environment. This composite action orchestrates the existing CompileApps and Sign actions together with the new CreateDevEnvironment, PublishApps and RunTests actions, and is the modular-build alternative to the classic RunPipeline action.

Requires `useCompilerFolder = true` (enforced by `useModularBuild`).

## Steps

1. **CreateDevEnvironment** – create the container, install dependency apps and the test toolkit
2. **CompileApps** – compile apps and test apps in a compiler folder (containerless)
3. **Sign** – sign the compiled apps (optional)
4. **PublishApps** – publish the compiled apps (and previous apps for upgrade)
5. **RunTests** – run tests / BCPT tests
6. **RemoveDevEnvironment** – capture the event log and remove the container (`if: always()`, honoring `keepEnvironment`)

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| token | | The GitHub token running the action | github.token |
| secretsJson | | The secrets (as returned by the ReadSecrets action) to pass to the build phases | '' |
| artifact | | ArtifactUrl to use for the build | '' |
| project | | Project folder | '.' |
| buildMode | | Specifies a mode to use for the build steps | Default |
| installAppsJson | | A path to a JSON-formatted list of apps to install | '' |
| installTestAppsJson | | A path to a JSON-formatted list of test apps to install | '' |
| baselineWorkflowRunId | | RunId of the baseline workflow run | '' |
| baselineWorkflowSHA | | SHA of the baseline workflow run | '' |
| previousAppsPath | | Path to folder containing previous release apps for upgrade testing | '' |
| signArtifacts | | Whether to sign the compiled apps | false |
| azureCredentialsJson | | Azure Credentials secret (Base 64 encoded) used for signing | '' |
| keepEnvironment | | Keep the development environment (container) after the build/test for debugging | false |

## OUTPUT

None
