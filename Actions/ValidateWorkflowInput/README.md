# Validate Workflow Input

Validate Workflow Input

## INPUT

Validation script for calling workflow must exist

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |

## OUTPUT

throws if validation script doesn't exist or any validated fields are invalid
