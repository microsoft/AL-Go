# Create Development Environment
Create an online development environment

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
| environmentName | Yes | Name of the online environment to create |
| project | | Project name if the repository is setup for multiple projects | . |
| adminCenterApiCredentials | | ClientId/ClientSecret or Refresh token for Admin Center API authentication | |
| reUseExistingEnvironment | | Reuse existing environment if it exists | N |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | Y if the action should create a direct commit against the branch or N to create a Pull Request | N |

## OUTPUT
none