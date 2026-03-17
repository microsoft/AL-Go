# Compile apps from workspace

Compile AL apps by using workspace compilation from the ALTool

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with secrets needed for appDependencyProbingPaths authentication must be read by a prior call to the ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| token | | The GitHub token running the action | github.token |
| artifact | | ArtifactUrl to use for the build (optional) | '' |
| project | | Project folder | '.' |
| buildMode | | Specifies a mode to use for the build steps | Default |
| dependencyAppsJson | | Path to a JSON file containing a list of dependency apps | '' |
| dependencyTestAppsJson | | Path to a JSON file containing a list of dependency test apps | '' |
| baselineWorkflowRunId | | RunId of the baseline workflow run | '' |
| baselineWorkflowSHA | | SHA of the baseline workflow run | '' |

## OUTPUT

None. Compiled apps are placed in `.buildartifacts/Apps` and `.buildartifacts/TestApps` where they are picked up by `Run-AlPipeline`'s prebuilt app detection in the RunPipeline step.
