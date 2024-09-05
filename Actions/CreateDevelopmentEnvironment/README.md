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
| environmentName | Yes | Name of the online environment to create |
| project | | Project name if the repository is setup for multiple projects | . |
| adminCenterApiCredentials | | ClientId/ClientSecret or Refresh token for Admin Center API authentication | |
| reUseExistingEnvironment | | Reuse existing environment if it exists? | false |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | true if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT

none
