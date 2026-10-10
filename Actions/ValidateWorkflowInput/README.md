# Validate Workflow Input

Validate Workflow Input

## INPUT

Validation script for calling workflow must exist

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| workflowName | | The name of the workflow for which the inputs are validated. *(override for reusable workflows, where github.workflow is the name of the calling workflow)* | github.workflow |
| inputsJson | | The workflow inputs in compressed JSON format, e.g. `${{ toJson(inputs) }}`. *(override for reusable workflows, where the event payload belongs to the calling workflow)* If not specified, the inputs are read from the GitHub event payload | '' |

## OUTPUT

throws if validation script doesn't exist or any validated fields are invalid
