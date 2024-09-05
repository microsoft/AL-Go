# Increment version number

Increment version number in AL-Go repository

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| actor | | The GitHub actor running the action | github.actor |
| token | | The GitHub token running the action | github.token |
| projects | | List of project names if the repository is setup for multiple projects (\* for all projects) | * |
| versionNumber | Yes | The version to update to. Use Major.Minor for absolute change, use +1 to bump to the next major version, use +0.1 to bump to the next minor version | |
| updateBranch | | Which branch should the app be added to | github.ref_name |
| directCommit | | true if the action should create a direct commit against the branch or false to create a Pull Request | false |

## OUTPUT

none
