param(
    [Parameter(Mandatory = $false, HelpMessage = "JSON-formatted array of branches to include if they exist. If not specified, all branches are returned. Wildcards are supported.")]
    [string] $includeBranchesJson = '[]'
)

$gitHubHelperPath = Join-Path $PSScriptRoot '../Github-Helper.psm1' -Resolve
Import-Module $gitHubHelperPath -DisableNameChecking

invoke-git fetch
$allBranches = @(invoke-git -returnValue for-each-ref --format="%(refname:short)" refs/remotes/origin | ForEach-Object { $_ -replace 'origin/', '' })

$includeBranches = ConvertFrom-Json $includeBranchesJson
if ($includeBranches) {
    Write-Host "Filtering branches by: $($includeBranches -join ', ')"
    $branches = @()
    foreach ($branchFilter in $includeBranches) {
        $branches += $allBranches | Where-Object { $_ -like $branchFilter }
    }
}
else {
    $branches = $allBranches
}

Write-Host "Found git branches: $($branches -join ', ')"

# Add the branches to the output
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Branches=$(ConvertTo-Json $branches -Depth 99 -Compress)"
