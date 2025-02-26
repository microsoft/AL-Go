# Get Workflow Multi-Run Branches

Gets the branches for a multi-branch workflow run.
If the worflow is dispatched, the branches are determined based on the input `includeBranches`.
If the workflow is run on a schedule, the branches are determined based on the `workflowSchedule.includeBranches` setting.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | false | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| includeBranches | false | Comma-separated value of branch name patterns to include if they exist. If not specified, only the current branch is returned. Wildcards are supported. |''|

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| Result | JSON-formatted object with `branches` property, an array of branch names |
