# Increment version number
Increment version number in AL-Go repository

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
| versionnumber | Yes | Updated Version Number. Use Major.Minor for absolute change, use +Major.Minor for incremental change | |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | Y if the action should create a direct commit against the branch or N to create a Pull Request | N |

## OUTPUT
none
