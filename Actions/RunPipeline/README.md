# Run pipeline

Run pipeline in AL-Go repository

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with licenseFileUrl, codeSignCertificateUrl, codeSignCertificatePassword, keyVaultCertificateUrl, keyVaultCertificatePassword, keyVaultClientId, gitHubPackagesContext, applicationInsightsConnectionString must be read by a prior call to the ReadSecets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| artifact | | ArtifactUrl to use for the build | settings.artifact |
| project | | Project name if the repository is setup for multiple projects | . |
| buildMode | | Specifies a mode to use for the build steps | Default |
| installAppsJson | | A path to a JSON-formatted list of apps to install | '' |
| installTestAppsJson | | A path to a JSON-formatted list of test apps to install | '' |
| baselineWorkflowRunId | RunId of the baseline workflow run | |
| baselineWorkflowSHA | SHA of the baseline workflow run | |

## OUTPUT

## ENV variables

| Name | Description |
| :-- | :-- |
| containerName | Container name of a container used during build |
| containerCredential | Masked, base64-encoded JSON credential for reconnecting to a container kept alive for the RunTests action |
| runTestsInSeparateAction | True only when RunPipeline kept a single local build container alive for the RunTests action |

## OUTPUT variables

none
