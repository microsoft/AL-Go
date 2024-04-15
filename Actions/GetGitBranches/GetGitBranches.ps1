param(
    $includeBranches = @()
)

invoke-git fetch
$allBranches = @(invoke-git for-each-ref --format="%(refname:short)" refs/remotes/origin | ForEach-Object { $_ -replace 'origin/', '' })

if ($includeBranches) {
    $branches = @()
    foreach ($branchFilter in $includeBranches) {
        $branches += $allBranches | Where-Object { $_ -like $branchFilter }
    }
}
else {
    $branches = $allBranches
}

# Add the branches to the output
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "branches=$(ConvertTo-Json $branches -Depth 99 -Compress)"
