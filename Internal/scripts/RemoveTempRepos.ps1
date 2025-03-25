param(
    [Parameter(Mandatory=$true, HelpMessage="The GitHub owner of the repositories to remove.")]
    [string] $githubOwner,
    [Parameter(Mandatory=$true, HelpMessage="The token use for the operation.")]
    [string] $token
)

$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
Import-Module (Join-Path "..\.." "e2eTests\e2eTestHelper.psm1") -DisableNameChecking

SetTokenAndRepository -github -githubOwner $githubOwner -token $token -repository ''

@(invoke-gh repo list $githubOwner --limit 1000 -silent -returnValue) | ForEach-Object { $_.Split("`t")[0] } | Where-Object { "$_" -like "$githubOwner/tmp*" } | ForEach-Object {
    $repo = $_
    Write-Host "https://github.com/$repo"
    $repoOwner = $repo.Split('/')[0]
    @((invoke-gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "/orgs/$repoOwner/packages?package_type=nuget" -silent -returnvalue -ErrorAction SilentlyContinue | ConvertFrom-Json)) | Where-Object { ($_.PSObject.Properties.Name -eq 'repository') -and ($_.repository.full_name -eq $repo) } | ForEach-Object {
        Write-Host "- package $($_.name)"
        # Pipe empty string into GH API --METHOD DELETE due to https://github.com/cli/cli/issues/3937
        '' | invoke-gh api --method DELETE -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "/orgs/$repoOwner/packages/nuget/$($_.name)" --input -
    }
    invoke-gh repo delete "https://github.com/$repo" --yes | Out-Host
}