# Analyze Tests

Analyze results of tests from the RunPipeline action

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| project | Yes | Name of project to analyze or . if the repository is setup for single project | |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| TestResultMD | MarkDown of the test result with \\n instead of line breaks |

### SUMMARY

This function will set the test result markdown in the GITHUB_STEP_SUMMARY section
