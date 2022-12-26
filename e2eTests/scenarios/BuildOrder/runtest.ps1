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

#  ____        _ _     _  ____          _           
# |  _ \      (_) |   | |/ __ \        | |          
# | |_) |_   _ _| | __| | |  | |_ __ __| | ___ _ __ 
# |  _ <| | | | | |/ _` | |  | | '__/ _` |/ _ \ '__|
# | |_) | |_| | | | (_| | |__| | | | (_| |  __/ |   
# |____/ \__,_|_|_|\__,_|\____/|_|  \__,_|\___|_|   
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

try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

    $repository = "$githubOwner/$repoName"
    $branch = "main"

    $template = "https://github.com/$($pteTemplate)@main"
    $runs = 0

    # Login
    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository -github:$github

    # Create repo
    CreateRepository -template $template -branch $branch -contentPath (Join-Path $PSScriptRoot 'content')
    $repoPath = (Get-Location).Path

    # Update AL-Go System Files
    Run-UpdateAlGoSystemFiles -templateUrl $template -wait -branch $branch -directCommit -ghTokenWorkflow $token | Out-Null
    $runs++

    # Run CI/CD workflow
    $run = Run-CICD -branch $branch
    $runs++

    # Launch Current, NextMinor and NextMajor builds
    $runTestCurrent = Run-TestCurrent -branch $branch
    $runTestNextMinor = Run-TestNextMinor -branch $branch -insiderSasToken $insiderSasToken
    $runTestNextMajor = Run-TestNextMajor -branch $branch -insiderSasToken $insiderSasToken

    # Wait for all workflows to finish
    WaitWorkflow -runid $run.id
    $runs++
    WaitWorkflow -runid $runTestCurrent.id
    $runs++
    WaitWorkflow -runid $runTestNextMinor.id
    $runs++
    WaitWorkflow -runid $runTestNextMajor.id
    $runs++

    Test-NumberOfRuns -expectedNumberOfRuns $runs
    
    Set-Location $prevLocation
    RemoveRepository -repository $repository -path $repoPath
}
catch {
    Write-Host $_.Exception.Message
    Write-Host "::Error::$($_.Exception.Message)"
    if ($github) {
        $host.SetShouldExit(1)
    }
}
finally {
    # Cleanup environments and other stuff
}
