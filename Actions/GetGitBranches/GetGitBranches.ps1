param(
    [Parameter(Mandatory = $false, HelpMessage = "Comma-separated value of branch names to include if they exist. If not specified, only the default branch is returned. Wildcards are supported.")]
    [string] $includeBranches = ''
)

$gitHubHelperPath = Join-Path $PSScriptRoot '../Github-Helper.psm1' -Resolve
Import-Module $gitHubHelperPath -DisableNameChecking

invoke-git fetch | Out-Null

$allBranches = @(invoke-git -returnValue for-each-ref --format="%(refname:short)" refs/remotes/origin | ForEach-Object { $_ -replace 'origin/', '' })
$branches = @()

if ($includeBranches) {
    $includeBranchesPatterns = $includeBranches -split ',' | ForEach-Object { $_.Trim() }
    Write-Host "Filtering branches by: $($includeBranchesPatterns -join ', ')"

    foreach ($branchPattern in $includeBranchesPatterns) {
        $branches += $allBranches | Where-Object { $_ -like $branchPattern }
    }

    $branches = $branches | Select-Object -Unique
}
else {
    $branches = $allBranches # return all branches
}

Write-Host "Found git branches: $($branches -join ', ')"

# Add the branches to the output
$ResultJSON = $(ConvertTo-Json @{ branches = $branches } -Depth 99 -Compress)
Write-Host "Result=$ResultJSON"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Result=$ResultJSON"
