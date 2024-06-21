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
| templateUrl | | URL of the template repository (default is the template repository used to create the repository) | default |
| downloadLatest | Yes | Set this input to true in order to download latest version of the template repository (else it will reuse the SHA from last update) | |
| update | | Set this input to Y in order to update AL-Go System Files if needed | N |
| updateBranch | | Set the branch to update. In case `directCommit` parameter is set to true, then the branch the action is run on will be updated | github.ref_name |
| directCommit | | True if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT

none
