# PostProcess action

Finalize a workflow by recording telemetry about its conclusion, duration, and AL-Go configuration.

This action is telemetry-only. Failures are visible in the logs but do not fail the workflow. Actual build and test failures are still enforced by the workflow's status checks.

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
