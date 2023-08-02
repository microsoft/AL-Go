# Deploy
Deploy Apps to online environment

## INPUT

### ENV variables
none

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| actor | | The GitHub actor running the action | github.actor |
| token | | The GitHub token running the action | github.token |
| parentTelemetryScopeJson | | Specifies the parent telemetry scope for the telemetry signal | {} |
| projects | | Comma separated list of projects to deploy. | |
| environmentName | Yes | Name of environment to deploy to |
| artifacts | Yes | Artifacts to deploy |
| type | | Type of delivery (CD or Release) | CD |

## OUTPUT
none
