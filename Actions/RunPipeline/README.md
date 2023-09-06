# Run pipeline
Run pipeline in AL-Go repository

## INPUT

### ENV variables
| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets with licenseFileUrl, insiderSasToken, codeSignCertificateUrl, codeSignCertificatePassword, keyVaultCertificateUrl, keyVaultCertificatePassword, keyVaultClientId, gitHubPackagesContext, applicationInsightsConnectionString must be read by a prior call to the ReadSecets Action |

### Parameters
| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The GitHub token running the action | github.token |
| parentTelemetryScopeJson | | Specifies the parent telemetry scope for the telemetry signal | {} |
| artifact | | ArtifactUrl to use for the build | settings.artifact |
| project | | Project name if the repository is setup for multiple projects | . |
| buildMode | | Specifies a mode to use for the build steps | Default |
| installAppsJson | | A JSON-formatted list of apps to install | [] |
| installTestAppsJson | | A JSON-formatted list of test apps to install | [] |

## OUTPUT

## ENV variables
| Name | Description |
| :-- | :-- |
| containerName | Container name of a container used during build |

## OUTPUT variables
none
