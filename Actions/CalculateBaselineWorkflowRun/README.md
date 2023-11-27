# Calculate Baseline WorkflowRun
Finds the latest CICD workflow run that completed and build all the AL-Go project successfully.

## INPUT

### ENV variables
none

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |

## OUTPUT

### ENV variables
none

### OUTPUT variables
| Name | Description |
| :-- | :-- |
| BaselineWorkflowRunId | The workflow run ID to use as a baseline
