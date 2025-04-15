# Enabling telemetry

If you want to enable partner telemetry add your Application Insights connection string to the AL-Go settings file. Simply add the following setting to your settings file:

```json
"PartnerTelemetryConnectionString":  "<connection string to your Application Insights>"
```

Per default, AL-Go logs some basic telemetry to Microsoft. If you want to opt-out of sending telemetry to Microsoft you can add the following setting to your settings file:

```json
"microsoftTelemetryConnectionString":  ""
```

By setting the Microsoft telemetry connection string to be an empty string you opt-out of sending basic telemetry to Microsoft. If on the other hand you want to send extended telemetry to Microsoft you can do that with the following setting.

```json
"SendExtendedTelemetryToMicrosoft" : true
```

Sending extended telemetry to Microsoft is helpful for when we need to help investigate an issue in your repository.

## Telemetry events and data

AL-Go logs four different types of telemetry events: AL-Go action ran/failed and AL-Go workflow ran/failed. Each of those telemetry events provide slightly different telemetry but common dimensions for all of them are:

**Common Dimensions**
| Dimension | Description |
|-----------|-------------|
| PowerShellVersion | The version of powershell used to run the action |
| BcContainerHelperVersion | The version of BcContainerHelper used to run the action (if imported) |
| WorkflowName | The name of the workflow |
| RunnerOs | The operating system of the runner |
| RunId | The Run Id |
| RunNumber | The Run Number |
| RunAttempt | The attempt number |
| Repository | The repository Id |

### AL-Go action ran

Telemetry message: AL-Go action ran

SeverityLevel: 1

Additional Dimensions: None

### AL-Go action failed

Telemetry message: AL-Go action failed

SeverityLevel: 3

Additional Dimensions:

| Dimension | Description |
|-----------|-------------|
| ErrorMessage | The error message thrown |

### AL-Go workflow ran

Telemetry message: AL-Go workflow ran

SeverityLevel: 1

Additional Dimensions:

| Dimension | Description |
|-----------|-------------|
| WorkflowConclusion | Success or Cancelled |
| WorkflowDuration | The duration of the workflow run |
| RepoType | AppSource or PTE |
| GitHubRunner | Value of the GitHubRunner setting |
| RunsOn | Value of the RunsOn setting |
| ALGoVersion | The AL-Go version used for the workflow run |

### AL-Go workflow failed

Telemetry message: AL-Go workflow failed

SeverityLevel: 3

Additional Dimensions:

| Dimension | Description |
|-----------|-------------|
| WorkflowConclusion | Failure or TimedOut |
| WorkflowDuration | The duration of the workflow run |
| RepoType | AppSource or PTE |
| GitHubRunner | Value of the GitHubRunner setting |
| RunsOn | Value of the RunsOn setting |
| ALGoVersion | The AL-Go version used for the workflow run |

______________________________________________________________________

[back](../README.md)
