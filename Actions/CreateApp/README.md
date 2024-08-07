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
| project | | Project name if the repository is setup for multiple projects | . |
| type | Yes | Type of app to add (PTE, AppSource App, Test App) | |
| name | Yes | App Name | |
| publisher | Yes | Publisher | |
| idrange | Yes | ID range | |
| sampleCode | | Include Sample Code? | false |
| sampleSuite | | Include Sample BCPT Suite? | false |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | true if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT

none
