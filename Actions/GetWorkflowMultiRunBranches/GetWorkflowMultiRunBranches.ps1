param(
    [Parameter(Mandatory = $false, HelpMessage = "Comma-separated value of branch names patterns to include if they exist. If not specified, all remote branches are returned. Wildcards are supported.")]
    [string] $includeBranches
)

$gitHubHelperPath = Join-Path $PSScriptRoot '../Github-Helper.psm1' -Resolve
Import-Module $gitHubHelperPath -DisableNameChecking

switch ($env:GITHUB_EVENT_NAME) {
    'schedule' {
      Write-Host "Event is schedule: getting branches from settings"
      $branchPatterns = @($($(ConvertFrom-Json $env:settings).workflowSchedule.includeBranches))
    }
    'workflow_dispatch' {
      Write-Host "Event is workflow_dispatch: getting branches from input"
      $branchPatterns = @($includeBranches.Split(',') | ForEach-Object { $_.Trim() })
    }
  }

# Default to the current branch if no branch patterns are specified
if (-not $branchPatterns) {
    $branchPatterns = @($env:GITHUB_REF_NAME)
}

Write-Host "Filtering branches by: $($branchPatterns -join ', ')"

invoke-git fetch --quiet
$allBranches = @(invoke-git -returnValue for-each-ref --format="%(refname:short)" refs/remotes/origin | ForEach-Object { $_ -replace 'origin/', '' })
$branches = @()

foreach ($branchPattern in $branchPatterns) {
    $branches += $allBranches | Where-Object { $_ -like $branchPattern }
}

$branches = $branches | Select-Object -Unique
Write-Host "Found git branches: $($branches -join ', ')"

# Add the branches to the output
$ResultJSON = $(ConvertTo-Json @{ branches = $branches } -Depth 99 -Compress)
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Result=$ResultJSON"
