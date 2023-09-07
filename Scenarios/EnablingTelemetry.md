# 15. Enabling telemetry

If you want to enable partner telemetry add your Application Insights connection string to the AL-GO settings file. the settings structure is:

```
"PartnerTelemetryConnectionString":  "<connection string to your Application Insights>"
```

You can also decide to send extended telelmetry to Microsoft. This would be helpful to investigate an issue. To enable the extended telemetry add the following property to the AL-GO settings file:

```
"SendExtendedTelemetryToMicrosoft" : true
```

Each workflow starts with initialization task and ends with a postprocess task. During the initialization an operation Id(Guid) is generated and added to all the tasks in the workflow as ParentID. This property can be used to see all the signals sent for a workflow. The postprocess task sends the signal and duration of a workflow. Additionally, each task has its own signal and operationId. This could be used to investigate a task.

Here is a list of the telemetry signals for different tasks:
| Event ID | Description |
| :-- | :-- |
| DO0070 | AL-Go action ran: AddExistingApp |
| DO0071 | AL-Go action ran: CheckForUpdates |
| DO0072 | AL-Go action ran: CreateApp |
| DO0073 | AL-Go action ran: CreateDevelopmentEnvironment |
| DO0074 | AL-Go action ran: CreateReleaseNotes |
| DO0075 | AL-Go action ran: Deploy |
| DO0076 | AL-Go action ran: IncrementVersionNumber |
| DO0077 | AL-Go action ran: PipelineCleanup |
| DO0078 | AL-Go action ran: ReadSecrets |
| DO0079 | AL-Go action ran: ReadSettings |
| DO0080 | AL-Go action ran: RunPipeline |
| DO0081 | AL-Go action ran: Deliver |
| DO0082 | AL-Go action ran: AnalyzeTests |
| DO0083 | AL-Go action ran: Sign |
| DO0084 | AL-Go action ran: DetermineArtifactUrl |
| DO0085 | AL-Go action ran: DetermineProjectsToBuild |

Here is a list of the telemetry signals for different workflows:

| Event ID | Description |
| :-- | :-- |
| DO0090 | AL-Go workflow ran: AddExistingAppOrTestApp |
| DO0091 | AL-Go workflow ran: CICD |
| DO0092 | AL-Go workflow ran: CreateApp |
| DO0093 | AL-Go workflow ran: CreateOnlineDevelopmentEnvironment |
| DO0094 | AL-Go workflow ran: CreateRelease |
| DO0095 | AL-Go workflow ran: CreateTestApp |
| DO0096 | AL-Go workflow ran: IncrementVersionNumber |
| DO0097 | AL-Go workflow ran: PublishToEnvironment |
| DO0098 | AL-Go workflow ran: UpdateGitHubGoSystemFiles |
| DO0099 | AL-Go workflow ran: NextMajor |
| DO0100 | AL-Go workflow ran: NextMinor |
| DO0101 | AL-Go workflow ran: Current |
| DO0102 | AL-Go workflow ran: CreatePerformanceTestApp |
| DO0103 | AL-Go workflow ran: PublishToAppSource |
| DO0104 | AL-Go workflow ran: PullRequestHandler |

---
[back](../README.md)
