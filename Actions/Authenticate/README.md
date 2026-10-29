# Authenticate to BC

Checks for Business Central authentication credentials and initiates device login when none are available.

Selects the first non-empty secret in the caller-supplied order, ignoring missing or empty values. Whitespace around keys is trimmed; empty list entries are rejected. No implicit fallback keys are added.

When credentials are present, records the selected secret's name in the job summary. Otherwise, appends the requested candidate names and device-login instructions to the summary without waiting for sign-in to complete. Invalid secret JSON or incomplete device-login results fail the action. Secret values are not written to logs or the summary.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| secrets | Yes | Authentication secrets JSON from the ReadSecrets action | |
| secretNames | Yes | Comma-separated secret keys in priority order; first non-empty value wins | |
| authType | Yes | Explicit authentication target: `AdminCenter` or `Environment` | |
| environmentName | For Environment | Environment name; must be empty for AdminCenter | Empty |

## OUTPUT

### ENV variables

none

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| deviceCode | Set only when device login is required. Passed to the subsequent job to complete authentication; not the user-facing sign-in code |
