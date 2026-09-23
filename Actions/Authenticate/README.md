# Authenticate

Checks the authentication secrets for Create Online Dev. Environment and Publish To Environment. If credentials are present, records the selected secret's name in the job summary without initiating device login.

Callers must provide `secretNames`, a comma-separated list of keys from ReadSecrets in priority order. The action selects the first non-empty value in that order, ignoring missing or empty values. Whitespace around keys is trimmed; empty list entries are rejected. The action does not add any implicit fallback keys.

Callers must also explicitly choose `authType`: `AdminCenter` or `Environment`. Environment authentication requires `environmentName`; Admin Center authentication requires it to be empty.

Create Online Dev. Environment requests `adminCenterApiCredentials` with `authType: AdminCenter`. Messages display its configured `adminCenterApiCredentialsSecretName` rather than the logical key. Publish To Environment requests `<environmentName>-AuthContext`, `<environmentName>_AuthContext`, then `AuthContext`, with `authType: Environment`. This preserves existing credential precedence while keeping the order under workflow control.

When credentials are missing, the summary lists every requested candidate in order.

If no credentials are available, initiates Business Central device-code authentication without waiting for sign-in to complete. Runs through `Invoke-AlGoAction.ps1` and loads BcContainerHelper using the packaged AL-Go helpers. The sign-in instructions are appended to the job summary. Invalid secret JSON or missing device-login results fail the action.

Secret JSON is passed through an environment variable rather than interpolated into PowerShell source. Secret values are not written to logs or the summary.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | Settings populated by the ReadSettings action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | PowerShell shell in which to run the action | powershell |
| secrets | Yes | Authentication secrets JSON from the ReadSecrets action | |
| secretNames | Yes | Comma-separated secret keys in priority order; first non-empty value wins | |
| authType | Yes | Explicit authentication target: `AdminCenter` or `Environment` | |
| environmentName | For Environment | Environment name; must be empty for AdminCenter | Empty |

## OUTPUT

| Name | Description |
| :-- | :-- |
| deviceCode | Set only when device login is required. Passed to the subsequent job to complete authentication; not the user-facing sign-in code |
