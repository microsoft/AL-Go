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

In order to get started with consuming AL-Go telemetry

### Getting Started with Data Explorer

AL-Go offers a template data explorer report that can be used as a starting point. In order to use this report do the following:

1. Download the telemetrydashboard.json file from [here](resources/telemetrydashboard.json)
1. Open the file in an editor and fill in the clusterUri and database
   - Database: Name of your application insights resource in Azure
   - Cluster URI: https://ade.applicationinsights.io/subscriptions/\<SubscriptionId>/resourcegroups/\<ResourceGroup>/providers/microsoft.insights/components/\<Application Insights Name>
1. Go to https://dataexplorer.azure.com/dashboards
1. In the top left corner, click on the allow next to "New Dashboard". Select "Import dashboard from file"
1. Select the edited json file and give the new dashboard a name

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

______________________________________________________________________

[back](../README.md)
