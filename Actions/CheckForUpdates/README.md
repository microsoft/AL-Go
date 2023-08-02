# Check for updates
Check for updates to AL-Go system files and perform the update if requested

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
| templateBranch | | Branch in template repository to use for the update | default branch |
| update | | Set this input to Y in order to update AL-Go System Files if needed | N |
| updateBranch | | Set the branch to update. In case `directCommit` parameter is set to 'Y', then the branch the action is run on will be updated | github.ref_name |
| directCommit | | Y if the action should create a direct commit against the branch or N to create a Pull Request | N |

## OUTPUT
none