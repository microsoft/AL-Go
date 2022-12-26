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
#  - Create a new repository based on the PTE template with the content from the common folder
#  - Set GitHubPackagesContext secret in common repo
#  - Run the "CI/CD" workflow in common repo
#  - Create a new repository based on the PTE template with the content from the w1 folder
#  - Set GitHubPackagesContext secret in w1 repo
#  - Create a new repository based on the PTE template with the content from the dk folder
#  - Set GitHubPackagesContext secret in dk repo
#  - Wait for "CI/CD" workflow from common repo to complete
#  - Check artifacts generated in common repo
#  - Run the "CI/CD" workflow from w1 repo and wait for completion
#  - Check artifacts generated in w1 repo
#  - Run the "CI/CD" workflow from dk repo and wait for completion
#  - Check artifacts generated in dk repo
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

    # Adjust app.json files
    Get-ChildItem -Path $PSScriptRoot -include 'app.json' -Recurse | ForEach-Object {
        $appJson = Get-Content -Path $_.FullName -Encoding UTF8 | ConvertFrom-Json
        $newId = ([GUID]::NewGuid().ToString())
        Replace-StringInFiles -path $PSScriptRoot -include 'app.json' -search $appJson.Id -replace $newId
        Write-Host "$($_.Directory) -> $newId"
        $appJson.id = $newId
        $appJson.application = "21.0.0.0"
        $appJson.runtime = "10.0"
        Set-Content -Path $_.FullName -Value ($appJson | ConvertTo-Json -Depth 99) -Encoding UTF8
    }

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
        -repository $repository `
        -name 'GitHubPackagesContext' `
        -value (@{"serverUrl"="https://nuget.pkg.github.com/$githubOwner/index.json";"token"=$token} | ConvertTo-Json -Compress)
    $repoPath = (Get-Location).Path

    Set-Location $commonRepoPath
    # Wait for CI/CD workflow of Common to finish
    WaitWorkflow -repository $commonRepository -runid $commonRun.id
    $runs++
    Test-ArtifactsFromRun -runid $commonRun.id -folder 'artifacts' -expectedNumberOfApps 3 -expectedNumberOfTestApps 0 -expectedNumberOfDependencies 0 -repoVersion '1.0' -appVersion '1.0'

    Set-Location $w1RepoPath
    $w1Run = Run-CICD -repository $w1Repository -branch $branch -wait
    Test-ArtifactsFromRun -runid $w1Run.id -folder 'artifacts' -expectedNumberOfApps 1 -expectedNumberOfTestApps 0 -expectedNumberOfDependencies 0 -repoVersion '1.0' -appVersion '1.0'

    Set-Location $repoPath
    $run = Run-CICD -repository $repository -branch $branch -wait
    Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedNumberOfApps 1 -expectedNumberOfTestApps 0 -expectedNumberOfDependencies 3 -repoVersion '1.0' -appVersion '1.0'

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
