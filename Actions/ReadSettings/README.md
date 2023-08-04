# Read settings
Read settings for AL-Go workflows

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
| project | | Project name if the repository is setup for multiple projects | . |
| getenvironments | | Specifies the pattern of the environments you want to retreive (or empty for no environments) | |
| includeProduction | | Specifies whether you want to include production environments | N |
| release | | Indicates whether this is called from a release pipeline | N |
| get | | Specifies which properties to get from the settings file, default is all | |

## OUTPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Settings | A compressed JSON structure with ALL AL-Go settings, independent of the get parameter. If project was not specified, this will only include repository settings. |

> **NOTE:** This method creates individual environment variables for every setting specified in the get parameter.


### OUTPUT variables
| Name | Description |
| :-- | :-- |
| GitHubRunnerJson | GitHubRunner in compressed Json format |
| GitHubRunnerShell | Shell for GitHubRunner jobs |
| EnvironmentsJson | Environments in compressed Json format |
| EnvironmentCount | Number of environments in array |
| UnknownEnvironment | Determines whether we are publishing to an unknown environment |
