# Add existing app

Add an existing app to an AL-Go for GitHub repository

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
| url | Yes | Direct Download Url of .app or .zip file to add to the repository | |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | true if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT

none
