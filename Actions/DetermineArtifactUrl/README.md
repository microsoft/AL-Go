# Determine artifactUrl
Determines the artifactUrl to use for a given project
## Parameters
### settingsJson
Settings from repository in compressed Json format
### secretsJson
Secrets from repository in compressed Json format
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal

## Outputs
### ArtifactUrl:
The ArtifactUrl to use
### ArtifactCacheKey:
The Cache Key to use for caching the artifacts when using CompilerFolder
