# PostProcess action

Finalize a workflow

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| telemetryScopeJson | | Telemetry scope generated during the workflow initialization | {} |
| currentJobContext | | The current job context | '' |
| actionsRepo | No | The repository of the action | github.action_repository |
| actionsRef | No | The ref of the action | github.action_ref |

## OUTPUT

none
