# Compile apps from workspace

Compile AL apps by invoking the workspace-based compiler pipeline used by AL-Go.

## INPUT

### ENV variables

none

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

> ℹ️ Additional compile-specific values (such as folders, compiler folder, analyzers, etc.) can be provided through environment variables or by extending the script logic.

## OUTPUT

none
