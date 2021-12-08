# Add existing app
Add an existing app to a AL-Go repository
## Parameters
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### project
Project name if the repository is setup for multiple projects
### type (required)
Type of apps in the repository (Per Tenant Extension, AppSource App)
### url (required)
Direct Download Url of .app or .zip file
### directCommit (default N)
Direct Commit (Y/N)
