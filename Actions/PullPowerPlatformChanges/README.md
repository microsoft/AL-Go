# Pull Power Platform Changes
Pull the Power Platform solution from the specified Power Platform environment

## INPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with delivery target context secrets must be read by a prior call to the ReadSecrets Action |

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| actor | | The GitHub actor running the action | github.actor |
| token | | The GitHub token running the action | github.token |
| actionsRepo | Yes | Owner/Repository@ref of AL-Go Actions repository used | |
| environmentName | Yes | Name of environment to pull changes from |
| solutionFolder | | Name of the solution to download and folder in which to download the solution | |
| deploymentEnvironmentsJson | Yes | The settings for all Deployment Environments | |
| updateBranch | | The branch to update | github.ref_name |
| directCommit | | true if the action should create a direct commit against the branch or false to create a Pull Request | false |


Either artifactsFolder or solutionFolder needs to be specified

## OUTPUT
| Name | Description |
| :-- | :-- |
| environmentUrl | The URL for the environment. This URL is presented in the Deploy Step in summary under the environment name |




## Parameters
### shell (default powershell)
Shell in which you want to run the action (powershell or pwsh)
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### solutionName
The Power Platform solution to get the changes from.
### deploySettings
The deploy settings
### authSettings
The auth settings
### directCommit
If true, the changes will be committed directly to the branch. If not, the changes will be committed to a branch named after the solution.
