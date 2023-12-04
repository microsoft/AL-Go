# Determine Baseline Workflow Run
Finds the latest CICD workflow run that completed and built all the AL-Go projects successfully.
This workflow run is to be used as a baseline for all the build jobs in the current workflow run in case incremental build is required.

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
| BaselineWorkflowRunId | The workflow run ID to use as a baseline. 0, if no baseline CICD was found.
