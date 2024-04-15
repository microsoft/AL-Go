# Get Git Branches
Gets current git branches defined on the remote repository

## INPUT

### ENV variables
none

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| includeBranches | | JSON-formatted array of branches to include if they exist. If not specified, all branches are returned. Wildcards are supported. ||

## OUTPUT

### ENV variables
none

### OUTPUT variables
| Name | Description |
| :-- | :-- |
| Branches | The list of branches on the remote repository |
