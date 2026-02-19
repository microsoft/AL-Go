Param(
    [Parameter(Mandatory = $false)]
    [string] $token = $ENV:GITHUB_TOKEN,
    [Parameter(Mandatory = $true)]
    [string] $environmentsMatrixJson,
    [Parameter(Mandatory = $true)]
    [string] $deployResult,
    [Parameter(Mandatory = $true)]
    [string] $artifactsVersion
)

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

# Extract PR number from artifactsVersion (format: PR_<number>)
$prNumber = $artifactsVersion.Substring(3)
$repo = $ENV:GITHUB_REPOSITORY
$triggerRef = $ENV:GITHUB_REF_NAME
$state = if ($deployResult -eq 'success') { 'success' } else { 'failure' }

$headers = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/vnd.github+json"
}

# Get PR branch ref
Write-Host "Resolving PR #$prNumber branch ref"
$pr = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/pulls/$prNumber" -Headers $headers
$prRef = $pr.head.ref
Write-Host "PR #$prNumber branch: $prRef"

# Parse environments from the matrix JSON
$matrix = $environmentsMatrixJson | ConvertFrom-Json
$environments = @($matrix.matrix.include | ForEach-Object { $_.environment })

foreach ($envName in $environments) {
    Write-Host "Tracking deployment for environment: $envName"
    $encodedEnv = [System.Uri]::EscapeDataString($envName)

    # Find the auto-created deployment (ref: trigger branch) to get its environment URL and then deactivate it
    $envUrl = $null
    try {
        $existingDeps = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/deployments?environment=$encodedEnv&ref=$triggerRef&per_page=5" -Headers $headers
        foreach ($dep in @($existingDeps)) {
            # Retrieve environment URL from the auto-created deployment
            if (-not $envUrl) {
                $statuses = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/deployments/$($dep.id)/statuses?per_page=1" -Headers $headers
                if ($statuses -and @($statuses).Count -gt 0 -and @($statuses)[0].environment_url) {
                    $envUrl = @($statuses)[0].environment_url
                }
            }
            # Deactivate the auto-created deployment so it no longer shows as active
            Write-Host "Deactivating auto-created deployment $($dep.id) (ref: $($dep.ref))"
            $inactiveBody = '{"state":"inactive"}'
            Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/deployments/$($dep.id)/statuses" -Method Post -Headers $headers -Body $inactiveBody -ContentType 'application/json' | Out-Null
        }
    }
    catch {
        Write-Host "::warning::Could not process auto-created deployment: $($_.Exception.Message)"
    }

    # Create deployment against the PR branch
    $deployBody = @{
        ref               = $prRef
        environment       = $envName
        auto_merge        = $false
        required_contexts = @()
        description       = "Deployed via PublishToEnvironment (PR #$prNumber)"
    } | ConvertTo-Json -Compress

    try {
        $deployment = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/deployments" -Method Post -Headers $headers -Body $deployBody -ContentType 'application/json'
        Write-Host "Created deployment $($deployment.id) against $prRef"

        $statusBody = @{
            state       = $state
            environment = $envName
            description = "Deployed PR #$prNumber to $envName"
        }
        if ($envUrl) { $statusBody['environment_url'] = $envUrl }
        $statusJson = $statusBody | ConvertTo-Json -Compress

        Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/deployments/$($deployment.id)/statuses" -Method Post -Headers $headers -Body $statusJson -ContentType 'application/json' | Out-Null
        Write-Host "Deployment status set to $state for $envName"
    }
    catch {
        Write-Host "::warning::Failed to create PR deployment for environment $envName`: $($_.Exception.Message)"
    }
}
