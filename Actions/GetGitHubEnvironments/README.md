# Determine Deployment Environments

Determines the environments to be used for a build or a publish

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| GITHUB_TOKEN | GITHUB_TOKEN must be set as an environment variable when calling this action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |

## OUTPUT

| GitHubEnvironments | GitHub Environments in compressed Json format |

### ENV variables
