# Publish Apps

**PREVIEW** — part of the modular build (`useModularBuild`).

Publish the compiled apps (and previous release apps for upgrade testing) from `.buildartifacts` into the development container created by the CreateDevEnvironment action. This is phase 2 of the modular build (CreateDevEnvironment → PublishApps → RunTests). Requires `useCompilerFolder = true`.

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
| previousAppsPath | | Path to folder containing previous release apps for upgrade testing | '' |

## OUTPUT

None

The action reads the pipeline context persisted by CreateDevEnvironment (to reuse the container and its credential) and updates it with the list of published apps.
