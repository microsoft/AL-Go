# Create a new app
Create a new app and add it to an AL-Go repository

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
| type | Yes | Type of app to add (PTE, AppSource App, Test App) | |
| name | Yes | App Name | |
| publisher | Yes | Publisher | |
| idrange | Yes | ID range | |
| sampleCode | | Include Sample Code (Y/N) | N |
| sampleSuite | | Include Sample BCPT Suite (Y/N) | N |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | Y if the action should create a direct commit against the branch or N to create a Pull Request | N |

## OUTPUT
none
