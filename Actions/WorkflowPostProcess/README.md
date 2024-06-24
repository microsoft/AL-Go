# PostProcess action

Finalize a workflow

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| eventId | Yes | The event id of the initiating workflow | |
| telemetryScopeJson | | Telemetry scope generated during the workflow initialization | {} |

## OUTPUT

none
