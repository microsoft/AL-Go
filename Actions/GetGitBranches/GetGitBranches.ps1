param(
    [Parameter(Mandatory = $false, HelpMessage = "JSON-formatted array branch names to include if they exist. If not specified, only the default branch is returned. Wildcards are supported.")]
    [string] $includeBranches = ''
)

$gitHubHelperPath = Join-Path $PSScriptRoot '../Github-Helper.psm1' -Resolve
Import-Module $gitHubHelperPath -DisableNameChecking

invoke-git fetch
$allBranches = @(invoke-git -returnValue for-each-ref --format="%(refname:short)" refs/remotes/origin | ForEach-Object { $_ -replace 'origin/', '' })

$branches = @()

if ($includeBranches) {
    $includeBranchesPatterns = $includeBranches -split ',' | ForEach-Object { $_.Trim() }
    Write-Host "Filtering branches by: $($includeBranchesPatterns -join ', ')"
    foreach ($branchPattern in $includeBranchesPatterns) {
        $branches += $allBranches | Where-Object { $_ -like $branchPattern }
    }

    # remove duplicates
    $branches = $branches | Select-Object -Unique
}
else {
    # Only include the default branch
    $defaultBranch = $(invoke-git symbolic-ref --short refs/remotes/origin/HEAD) -replace 'origin/', ''
    $branches += $defaultBranch
}


Write-Host "Found git branches: $($branches -join ', ')"

# Add the branches to the output
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Branches=$(ConvertTo-Json $branches -Depth 99 -Compress)"
