# Determine whether to build project

Determine whether to build project

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| skippedProjectsJson | Yes | Compressed JSON string containing the list of projects that should be skipped | |
| project | Yes | Name of the project to build | |
| baselineWorkflowRunId | Yes | Id of the baseline workflow run, from which to download artifacts if build is skipped | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| BuildIt | True if the project should be built |
