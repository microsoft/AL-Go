# Deliver
Deliver App to AppSource or Storage
## Parameters
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### projects (default '*')
Projects to deliver  
### deliveryTarget (required)
Deliver to AppSource or Storage account
### artifacts (required)
The artifacts to deliver
### type (default 'CD')
Type of delivery
### atypes (default 'Apps,Dependencies,TestApps')
Types of artifacts to deliver
### goLive (default 'N')
Promote AppSource App to Go Live?
