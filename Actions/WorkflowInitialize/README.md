# Initialize workflow

Initialize a workflow

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| actionsRepo | No | The repository of the action | github.action_repository |
| actionsRef | No | The ref of the action | github.action_ref |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| telemetryScopeJson | A telemetryScope that covers the workflow |
