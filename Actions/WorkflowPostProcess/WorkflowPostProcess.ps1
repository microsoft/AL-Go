Param(
    [Parameter(HelpMessage = "Telemetry scope generated during the workflow initialization", Mandatory = $false)]
    [string] $telemetryScopeJson = '',
    [Parameter(HelpMessage = "The current job context", Mandatory = $false)]
    [string] $currentJobContext = '',
    [Parameter(HelpMessage = "The repository of the action", Mandatory = $false)]
    [string] $actionsRepo,
    [Parameter(HelpMessage = "The ref of the action", Mandatory = $false)]
    [string] $actionsRef
)

function GetWorkflowConclusion($JobContext) {
    # Check the conclusion for the current job
    if ($JobContext -ne '') {
        $jobContext = $JobContext | ConvertFrom-Json
        if ($jobContext.status -eq 'failure') {
            return "Failure"
        }
        if ($jobContext.status -eq 'timed_out') {
            return "TimedOut"
        }
        if ($jobContext.status -eq 'cancelled') {
            return "Cancelled"
        }
    }

    # Check the conclusion for the past jobs in the workflow
    $workflowJobs = gh api /repos/$ENV:GITHUB_REPOSITORY/actions/runs/$ENV:GITHUB_RUN_ID/jobs --paginate -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json
    if ($null -ne $workflowJobs) {
        $failedJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "failure" }
        if ($null -ne $failedJobs) {
            return "Failure"
        }
        $timedOutJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "timed_out" }
        if ($null -ne $timedOutJobs) {
            return "TimedOut"
        }
        $cancelledJobs = $workflowJobs.jobs | Where-Object { $_.conclusion -eq "cancelled" }
        if ($null -ne $cancelledJobs) {
            return "Cancelled"
        }
    }

    return "Success"
}

function GetAlGoVersion($ActionsRepo, $ActionRef) {
    Write-Host "ActionsRepo: $ActionsRepo, ActionRef: $ActionRef"
    if ($ActionsRepo -eq "microsoft/AL-Go") {
        return "Preview"
    } elseif($ActionsRepo -notlike "microsoft/*") {
        return "Developer/Private"
    } else {
        return $ActionRef
    }
}

function LogWorkflowEnd($TelemetryScopeJson, $JobContext, $AlGoVersion) {
    [System.Collections.Generic.Dictionary[[System.String], [System.String]]] $AdditionalData = @{}
    $telemetryScope = $null
    if ($TelemetryScopeJson -ne '') {
        $telemetryScope = $TelemetryScopeJson | ConvertFrom-Json
    }

    # Get the workflow conclusion
    $workflowConclusion = GetWorkflowConclusion -JobContext $JobContext
    Add-TelemetryProperty -Hashtable $AdditionalData -Key 'WorkflowConclusion' -Value $workflowConclusion

    # Calculate the workflow duration using the github api
    if ($telemetryScope -and ($null -ne $telemetryScope.workflowStartTime)) {
        Write-Host "Calculating workflow duration..."
        $workflowTiming= [DateTime]::UtcNow.Subtract([DateTime]::Parse($telemetryScope.workflowStartTime)).TotalSeconds
        Add-TelemetryProperty -Hashtable $AdditionalData -Key 'WorkflowDuration' -Value $workflowTiming
    }

    # Log additional telemetry from AL-Go settings
    $alGoSettingsPath = "$ENV:GITHUB_WORKSPACE/.github/AL-Go-Settings.json"
    if (Test-Path -Path $alGoSettingsPath) {
        $repoSettings = Get-Content -Path $alGoSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($repoSettings.PSObject.Properties.Name -contains 'type') {
            Add-TelemetryProperty -Hashtable $AdditionalData -Key 'RepoType' -Value $repoSettings.type
        }

        if ($repoSettings.PSObject.Properties.Name -contains 'githubRunner') {
            Add-TelemetryProperty -Hashtable $AdditionalData -Key 'GitHubRunner' -Value $repoSettings.githubRunner
        }

        if ($repoSettings.PSObject.Properties.Name -contains 'runs-on') {
            Add-TelemetryProperty -Hashtable $AdditionalData -Key 'RunsOn' -Value $repoSettings.'runs-on'
        }
    }

    if ($AlGoVersion -ne '') {
        Add-TelemetryProperty -Hashtable $AdditionalData -Key 'ALGoVersion' -Value $AlGoVersion
    }

    if ($workflowConclusion -in @("Failure", "TimedOut")) {
        Trace-Exception -Message "AL-Go workflow failed: $($ENV:GITHUB_WORKFLOW.Trim())" -AdditionalData $AdditionalData
    } else {
        Trace-Information -Message "AL-Go workflow ran: $($ENV:GITHUB_WORKFLOW.Trim())" -AdditionalData $AdditionalData
    }
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)

try {
    LogWorkflowEnd -TelemetryScopeJson $telemetryScopeJson -JobContext $currentJobContext -AlGoVersion (GetAlGoVersion -ActionsRepo $actionsRepo -ActionRef $actionsRef)
} catch {
    # Log the exception to telemetry but don't fail the action if gathering telemetry fails
    Write-Host "::Warning::Unexpected error when running action. Error Message: $($_.Exception.Message.Replace("`r",'').Replace("`n",' ')), StackTrace: $($_.ScriptStackTrace.Replace("`r",'').Replace("`n",' <- '))";
    Trace-Exception -ActionName "WorkflowPostProcess" -ErrorRecord $_
}
