# Check for updates
Check for updates to AL-Go system files
## Parameters
### actor (default github.actor)
The GitHub actor running the action
### token (default github.token)
The GitHub token running the action
### parentTelemetryScopeJson (default {})
Specifies the parent telemetry scope for the telemetry signal
### update (default N)
Set this input to Y in order to update AL-Go System Files if needed
### updateBranch (default github.ref_name)
Set the branch to update. In case `directCommit` parameter is set to 'Y', then the branch the action is run on will be updated. 
### directCommit (default N)
Direct Commit (Y/N)
