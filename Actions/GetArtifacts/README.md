# Deploy
Deploy App to online environment
## Parameters
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### workflow (required)
Name of workflow initiating the deployment (CI | Create Release)
### artifactsUrl (required)
Url of artifacts to deploy
