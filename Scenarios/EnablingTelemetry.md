# Enabling telemetry

If you want to enable partner telemetry add your Application Insights connection string to the AL-Go settings file. Simply add the following setting to your settings file:

```
"PartnerTelemetryConnectionString":  "<connection string to your Application Insights>"
```

Per default, AL-Go logs some basic telemetry to Microsoft. If you want to opt-out of sending telemetry to Microsoft you can add the following setting to your settings file:

```
"microsoftTelemetryConnectionString":  ""
```

By setting the Microsoft telemetry connection string to be an empty string you opt-out of sending basic telemetry to Microsoft. If on the other hand you want to send extended telemetry to Microsoft you can do that with the following setting.

```
"SendExtendedTelemetryToMicrosoft" : true
```

Sending extended telemetry to Microsoft is helpful for when we need to help investigate an issue in your repository.

## Getting Started with Dashboard and Queries

### Getting Started with Data Explorer

AL-Go provides a template Azure Data Explorer dashboard to help you monitor workflow reliability, inspect workflow and action runs, review test results, compare workflow duration and runner usage, and track AL-Go maintenance information across repositories.

The dashboard reports missing telemetry as **No telemetry** rather than treating missing data as a successful or healthy result. Test telemetry is emitted only when AL-Go executes at least one AL test, page scripting test, or BCPT test, so repositories without test runs don't populate the Tests & Quality page.

The Run Explorer includes raw action error messages. Grant access to the dashboard and underlying Application Insights resource only to operators who are allowed to see repository operational details. The dashboard uses a five-minute query results cache to reduce repeated query load and doesn't enable automatic refresh by default.

The **Execution Runtime & Supportability** table shows the latest observed AL-Go and PowerShell runtime per repository, together with the latest action in the selected range that reported BcContainerHelper as loaded. **Not loaded/reported** doesn't indicate an installation failure. Optionally enter an expected BcContainerHelper version on the AL-Go Maintenance page to identify repositories that differ from your organizational baseline.

To use this dashboard:

1. Download the [telemetry dashboard JSON](resources/telemetrydashboard.json).
1. Open the file in an editor and replace the clusterUri and database:
   - **database**: Name of your Application Insights resource in Azure
   - **clusterUri**: Use the following uri but replace YourSubscriptionId, YourResourceGroup and YourApplicationInsightsName
     - https://ade.applicationinsights.io/subscriptions/YourSubscriptionId/resourcegroups/YourResourceGroup/providers/microsoft.insights/components/YourApplicationInsightsName
1. Go to [Azure Data Explorer dashboards](https://dataexplorer.azure.com/dashboards).
1. In the top-left corner, select the arrow next to **New Dashboard**, and then select **Import dashboard from file**.
1. Open each page and verify its queries against representative workflow, action, test, and deprecation telemetry. An empty Tests & Quality page is expected when no tests ran in the selected time range.

### Getting Started with writing your own queries

To get started with writing kusto queries for your AL-Go telemetry, you can use the following examples as inspiration.

The following query gets all telemetry emitted when an AL-Go workflow completes.

```
traces
| where timestamp > ago(7d)
| project   timestamp,
            message,
            severityLevel,
            RepositoryOwner = tostring(customDimensions.RepositoryOwner),
            RepositoryName = tostring(customDimensions.RepositoryName),
            RunId = tostring(customDimensions.RunId),
            RunNumber = tostring(customDimensions.RunNumber),
            RunAttempt = tostring(customDimensions.RunAttempt),
            WorkflowName = tostring(customDimensions.WorkflowName),
            WorkflowConclusion = tostring(customDimensions.WorkflowConclusion),
            WorkflowDurationMinutes = round(todouble(customDimensions.WorkflowDuration) / 60, 2),
            ALGoVersion = tostring(customDimensions.ALGoVersion),
            RefName = tostring(customDimensions.RefName)
| extend HtmlUrl = strcat("https://github.com/", RepositoryName, "/actions/runs/", RunId)
| where message contains "AL-Go workflow"
```

The following query gets all telemetry emitted when an AL-Go action completes.

```
traces
| where timestamp > ago(7d)
| project   timestamp,
            message,
            severityLevel,
            RepositoryOwner = tostring(customDimensions.RepositoryOwner),
            RepositoryName = tostring(customDimensions.RepositoryName),
            RunId = tostring(customDimensions.RunId),
            RunNumber = tostring(customDimensions.RunNumber),
            RunAttempt = tostring(customDimensions.RunAttempt),
            WorkflowName = tostring(customDimensions.WorkflowName),
            WorkflowConclusion = tostring(customDimensions.WorkflowConclusion),
            WorkflowDuration = todouble(customDimensions.WorkflowDuration),
            ALGoVersion = tostring(customDimensions.ALGoVersion),
            RefName = tostring(customDimensions.RefName),
            RunnerOs = tostring(customDimensions.RunnerOs),
            RunnerEnvironment = tostring(customDimensions.RunnerEnvironment),
            ErrorMessage = tostring(customDimensions.ErrorMessage),
            ActionDurationSeconds = todouble(customDimensions.ActionDuration)
| extend HtmlUrl = strcat("https://github.com/", RepositoryName, "/actions/runs/", RunId)
| where message contains "AL-Go action"
```

The following query gets all telemetry emitted for test results

```
traces
| where timestamp > ago(7d)
| project   timestamp,
            message,
            severityLevel,
            RepositoryOwner = tostring(customDimensions.RepositoryOwner),
            RepositoryName = tostring(customDimensions.RepositoryName),
            RunId = tostring(customDimensions.RunId),
            RunNumber = tostring(customDimensions.RunNumber),
            RunAttempt = tostring(customDimensions.RunAttempt),
            RefName = tostring(customDimensions.RefName),
            TotalTests = todouble(customDimensions.TotalTests),
            TotalFailed = todouble(customDimensions.TotalFailed),
            TotalSkipped = todouble(customDimensions.TotalSkipped),
            TotalPassed = todouble(customDimensions.TotalPassed),
            TotalTime = todouble(customDimensions.TotalTime)
| extend HtmlUrl = strcat("https://github.com/", RepositoryName, "/actions/runs/", RunId)
| where message contains "AL-Go Test Results"
```

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

Additional Dimensions:
| Dimension | Description |
|-----------|-------------|
| ActionDuration | The duration of the action |

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

### Test results

Telemetry messages:

- `AL-Go Test Results - Tests`
- `AL-Go Test Results - Page scripting Tests`
- `AL-Go Test Results - BCPT Tests`

SeverityLevel: 1

Additional Dimensions:

| Dimension | Description |
|-----------|-------------|
| TotalTests | The total number of tests executed |
| TotalFailed | The number of tests that failed |
| TotalSkipped | The number of tests that were skipped |
| TotalPassed | The number of tests that passed |
| TotalTime | The total time taken to execute all tests |

**Note:** The `TotalTime` dimension is not tracked for BCPT test results. For BCPT tests, only `TotalTests`, `TotalPassed`, `TotalFailed`, and `TotalSkipped` are available.

______________________________________________________________________

[back](../README.md)
