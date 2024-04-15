param(
    [Parameter(Mandatory = $false, HelpMessage = "JSON-formatted array of branches to include if they exist. If not specified, all branches are returned. Wildcards are supported.")]
    [string] $includeBranches = '[]'
)

Import-Module '..\Github-Helper.psm1' -DisableNameChecking

invoke-git fetch
$allBranches = @(invoke-git for-each-ref --format="%(refname:short)" refs/remotes/origin | ForEach-Object { $_ -replace 'origin/', '' })

$includeBranches = ConvertFrom-Json $includeBranches

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
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Branches=$(ConvertTo-Json $branches -Depth 99 -Compress)"
