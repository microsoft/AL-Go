Param(
    [Parameter(Mandatory = $false)]
    [string] $token = $ENV:GITHUB_TOKEN,
    [Parameter(Mandatory = $true)]
    [string] $environmentsMatrixJson,
    [Parameter(Mandatory = $true)]
    [string] $deployResult,
    [Parameter(Mandatory = $true)]
    [string] $artifactsVersion,
    [Parameter(Mandatory = $false)]
    [string] $sha = $ENV:GITHUB_SHA
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

<#
    .SYNOPSIS
        Deactivate auto-created deployments and retrieve the environment URL.
    .DESCRIPTION
        The environment: key on the Deploy job auto-creates a deployment against the trigger ref (e.g. main).
        This function finds those deployments, retrieves the environment URL from the latest status, and
        deactivates them so they no longer show as active.
#>
function DeactivateAutoDeployments {
    Param(
        [hashtable] $headers,
        [string] $repository,
        [string] $environmentName,
        [string] $triggerRef,
        [string] $sha
    )

    $apiBase = "https://api.github.com/repos/$repository"
    $encodedEnv = [System.Uri]::EscapeDataString($environmentName)
    $envUrl = $null

    $listUri = "$apiBase/deployments?environment=$encodedEnv&ref=$triggerRef&sha=$sha&per_page=1"
    OutputDebug "GET $listUri"
    $existingDeps = (InvokeWebRequest -Headers $headers -Uri $listUri).Content | ConvertFrom-Json
    if ($existingDeps -and @($existingDeps).Count -gt 0) {
        $dep = @($existingDeps)[0]
        OutputDebug "Found auto-created deployment $($dep.id) (ref: $($dep.ref), sha: $($dep.sha))"
        $statusesUri = "$apiBase/deployments/$($dep.id)/statuses?per_page=1"
        OutputDebug "GET $statusesUri"
        $statuses = (InvokeWebRequest -Headers $headers -Uri $statusesUri).Content | ConvertFrom-Json
        if ($statuses -and @($statuses).Count -gt 0) {
            OutputDebug "Latest status: state=$(@($statuses)[0].state), environment_url=$(@($statuses)[0].environment_url)"
            if (@($statuses)[0].environment_url) {
                $envUrl = @($statuses)[0].environment_url
            }
            if (@($statuses)[0].state -ne 'inactive') {
                Write-Host "Deactivating auto-created deployment $($dep.id) (ref: $($dep.ref))"
                $deactivateUri = "$apiBase/deployments/$($dep.id)/statuses"
                OutputDebug "POST $deactivateUri (state: inactive)"
                InvokeWebRequest -Headers $headers -Method 'POST' -Uri $deactivateUri -Body '{"state":"inactive"}' | Out-Null
            }
            else {
                Write-Host "Auto-created deployment $($dep.id) is already inactive, skipping"
            }
        }
    }
    else {
        OutputDebug "No auto-created deployment found for environment=$environmentName, ref=$triggerRef, sha=$sha"
    }

    return $envUrl
}

<#
    .SYNOPSIS
        Create a deployment record against the PR branch and set its status.
#>
function CreatePRDeployment {
    Param(
        [hashtable] $headers,
        [string] $repository,
        [string] $prRef,
        [string] $prNumber,
        [string] $environmentName,
        [string] $environmentUrl,
        [string] $state
    )

    $apiBase = "https://api.github.com/repos/$repository"

    $deployBody = @{
        ref               = $prRef
        environment       = $environmentName
        auto_merge        = $false
        required_contexts = @()
        description       = "Deployed via PublishToEnvironment (PR #$prNumber)"
    } | ConvertTo-Json -Compress

    $createUri = "$apiBase/deployments"
    OutputDebug "POST $createUri (ref: $prRef, environment: $environmentName)"
    $deployment = (InvokeWebRequest -Headers $headers -Method 'POST' -Uri $createUri -Body $deployBody).Content | ConvertFrom-Json
    Write-Host "Created deployment $($deployment.id) against $prRef"

    $statusBody = @{
        state       = $state
        environment = $environmentName
        description = "Deployed PR #$prNumber to $environmentName"
    }
    if ($environmentUrl) { $statusBody['environment_url'] = $environmentUrl }
    $statusJson = $statusBody | ConvertTo-Json -Compress

    $statusUri = "$apiBase/deployments/$($deployment.id)/statuses"
    OutputDebug "POST $statusUri (state: $state)"
    InvokeWebRequest -Headers $headers -Method 'POST' -Uri $statusUri -Body $statusJson | Out-Null
    Write-Host "Deployment status set to $state for $environmentName"
}

# Main
$prNumber = $artifactsVersion.Substring(3)
$repo = $ENV:GITHUB_REPOSITORY
$triggerRef = $ENV:GITHUB_REF_NAME
$state = if ($deployResult -eq 'success') { 'success' } else { 'failure' }

OutputDebug "PR number: $prNumber, repository: $repo, triggerRef: $triggerRef, sha: $sha, deployResult: $deployResult"

$headers = GetHeaders -token $token

# Get PR branch ref using existing helper from Deploy.psm1
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\Deploy\Deploy.psm1" -Resolve)
$prRef = GetHeadRefFromPRId -repository $repo -prId $prNumber -token $token
if (-not $prRef) {
    throw "Could not determine PR branch for PR #$prNumber"
}
Write-Host "PR #$prNumber branch: $prRef"

# Parse environments from the matrix JSON
$matrix = $environmentsMatrixJson | ConvertFrom-Json
$environments = @($matrix.matrix.include | ForEach-Object { $_.environment })
OutputDebug "Environments to process: $($environments -join ', ')"

foreach ($envName in $environments) {
    Write-Host "Tracking deployment for environment: $envName"

    $envUrl = $null
    try {
        $envUrl = DeactivateAutoDeployments -headers $headers -repository $repo -environmentName $envName -triggerRef $triggerRef -sha $sha
    }
    catch {
        OutputWarning -message "Could not deactivate auto-created deployment for $envName`: $($_.Exception.Message)"
    }

    try {
        CreatePRDeployment -headers $headers -repository $repo -prRef $prRef -prNumber $prNumber -environmentName $envName -environmentUrl $envUrl -state $state
    }
    catch {
        OutputWarning -message "Failed to create PR deployment for $envName`: $($_.Exception.Message)"
    }
}
