# Compile apps from workspace

Compile AL apps by invoking the workspace-based compiler pipeline used by AL-Go.

## INPUT

### ENV variables

none

### Parameters

This action deliberately mirrors the inputs exposed by the `RunPipeline` action so that automation using one can easily call the other.

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell |  | The shell (powershell or pwsh) in which the PowerShell script should run | powershell |
| token |  | The GitHub token running the action | github.token |
| artifact |  | ArtifactUrl to use for the build (optional) | '' |
| project |  | Project folder | '.' |
| buildMode |  | Specifies a mode to use for the build steps | Default |
| installAppsJson |  | A JSON-formatted list of apps to install | [] |
| installTestAppsJson |  | A JSON-formatted list of test apps to install | [] |
| baselineWorkflowRunId |  | RunId of the baseline workflow run | '' |
| baselineWorkflowSHA |  | SHA of the baseline workflow run | '' |

> ℹ️ Additional compile-specific values (such as folders, compiler folder, analyzers, etc.) can be provided through environment variables or by extending the script logic.

## OUTPUT

none
