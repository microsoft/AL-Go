# Dump Workflow Info

Dump workflow info

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| workflowEventName | | The GitHub event name that triggered the workflow. Inputs are dumped for `workflow_dispatch` and `workflow_call`. *(override for reusable workflows, where github.event_name is the event of the calling workflow)* | github.event_name |
| inputsJson | | The workflow inputs in compressed JSON format, e.g. `${{ toJson(inputs) }}`. *(override for reusable workflows, where the event payload belongs to the calling workflow)* If not specified, the inputs are read from the GitHub event payload | '' |

## OUTPUT

none
