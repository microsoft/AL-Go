Param(
    [switch] $github,
    [string] $githubOwner = "businesscentralapps",
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($E2EPATSecret.SecretValue | Get-PlainText),
    [string] $pteTemplate = "$(invoke-git config user.name -silent -returnValue)/AL-Go-PTE@main",
    [string] $appSourceTemplate = "$(invoke-git config user.name -silent -returnValue)/AL-Go-AppSource@main",
    [string] $adminCenterApiToken = ($AdminCenterApiCredentialsSecret.SecretValue | Get-PlainText),
    [string] $licenseFileUrl = ($LicenseFileUrlSecret.SecretValue | Get-PlainText),
    [string] $insiderSasToken = ($InsiderSasTokenSecret.SecretValue | Get-PlainText)
)

#
# This test tests the following scenarios:
#                                                                                                      
#  - Create a new repository based on the PTE template with the content from the content folder
#  - Run Update AL-Go System Files to apply settings from the app
#  - Run the "CI/CD" workflow
#  - Run the Test Current Workflow
#  - Run the Test Next Minor Workflow
#  - Run the Test Next Major Workflow
#  - Test that runs were successful and artifacts were created
#  - Cleanup repositories
#
  
$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0
$prevLocation = Get-Location
$repoPath = ""

#try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

    $repository = "$githubOwner/$repoName"
    $branch = "main"

    $template = "https://github.com/$($pteTemplate)@main"
    $runs = 0

    # Login
    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository -github:$github

    $commonRepository = "$repository.Common"
    $w1Repository = "$repository.W1"

    # Create common repo
    CreateRepository -linux `
        -template $template `
        -repository $commonRepository `
        -branch $branch `
        -contentPath (Join-Path $PSScriptRoot 'Common') `
        -applyAlGoSettings @{ "country" = "w1" }
    SetRepositorySecret `
        -repository $commonRepository `
        -name 'GitHubPackagesContext' `
        -value (@{"serverUrl"="https://nuget.pkg.github.com/$githubOwner/index.json";"token"=$token} | ConvertTo-Json -Compress)
    $commonRepoPath = (Get-Location).Path
    $commonRun = Run-CICD -repository $commonRepository -branch $branch

    # Create W1 repo
    CreateRepository -linux `
        -template $template `
        -repository $w1Repository `
        -branch $branch `
        -contentPath (Join-Path $PSScriptRoot 'W1') `
        -applyAlGoSettings @{ "country" = "w1" }
    SetRepositorySecret `
        -repository $w1Repository `
        -name 'GitHubPackagesContext' `
        -value (@{"serverUrl"="https://nuget.pkg.github.com/$githubOwner/index.json";"token"=$token} | ConvertTo-Json -Compress)
    $w1RepoPath = (Get-Location).Path

    # Create DK repo
    CreateRepository -linux `
        -template $template `
        -repository $repository `
        -branch $branch `
        -contentPath (Join-Path $PSScriptRoot 'DK') `
        -applyRepoSettings @{ "generateDependencyArtifact" = $true } `
        -applyAlGoSettings @{ "country" = "dk" }
    SetRepositorySecret `
        -repository $w1Repository `
        -name 'GitHubPackagesContext' `
        -value (@{"serverUrl"="https://nuget.pkg.github.com/$githubOwner/index.json";"token"=$token} | ConvertTo-Json -Compress)
    $repoPath = (Get-Location).Path

    # Wait for CI/CD workflow of Common to finish
    WaitWorkflow -repository $commonRepository -runid $commonRun.id
    $runs++

    Test-ArtifactsFromRun -runid $commonRun.id -folder 'commonartifacts' -expectedNumberOfApps 3 -expectedNumberOfTestApps 0 -expectedNumberOfDependencies 0 -repoVersion '1.0' -appVersion '1.0'

    $w1Run = Run-CICD -repository $w1Repository -branch $branch -wait

    Test-ArtifactsFromRun -runid $commonRun.id -folder 'w1artifacts' -expectedNumberOfApps 1 -expectedNumberOfTestApps 0 -expectedNumberOfDependencies 0 -repoVersion '1.0' -appVersion '1.0'

    $run = Run-CICD -repository $repository -branch $branch -wait

    Test-ArtifactsFromRun -runid $run -folder 'artifacts' -expectedNumberOfApps 1 -expectedNumberOfTestApps 0 -expectedNumberOfDependencies 3 -repoVersion '1.0' -appVersion '1.0'

    Set-Location $prevLocation
    RemoveRepository -repository $repository -path $repoPath
    RemoveRepository -repository $w1repository -path $w1RepoPath
    RemoveRepository -repository $commonRepository -path $commonRepoPath
#}
#catch {
#    Write-Host $_.Exception.Message
#    Write-Host "::Error::$($_.Exception.Message)"
#    if ($github) {
#        $host.SetShouldExit(1)
#    }
#}
#finally {
#    # Cleanup environments and other stuff
#}
