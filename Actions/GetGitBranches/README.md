# Get Git Branches

Gets current git branches defined on the remote repository

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | false | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| includeBranches | false | Comma-separated value of branch names to include if they exist. If not specified, only the default branch is returned. Wildcards are supported. |''|

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| Branches | JSON-formatted array of branch names |
