Param(
    [string] $githubOwner = "",
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = "",
    [string] $pteTemplate = "",
    [string] $appSourceTemplate = "",
    [string] $adminCenterApiCredentials = "",
    [string] $licenseFileUrl = "",
    [string] $insiderSasToken = ""
)

#  ____        _ _     _  ____          _           
# |  _ \      (_) |   | |/ __ \        | |          
# | |_) |_   _ _| | __| | |  | |_ __ __| | ___ _ __ 
# |  _ <| | | | | |/ _` | |  | | '__/ _` |/ _ \ '__|
# | |_) | |_| | | | (_| | |__| | | | (_| |  __/ |   
# |____/ \__,_|_|_|\__,_|\____/|_|  \__,_|\___|_|   
#                                                 #
# This test tests the following scenarios:
#                                                                                                      
#  1. Login to GitHub
#  2. Create a new repository based on the PTE template with the app from the appfolder
#  3. Run Update AL-Go System Files to apply settings from the app
#  4. Run the "CI/CD" workflow
#  5. Run the Test Current Workflow
#  6. Run the Test Next Minor Workflow
#  7. Run the Test Next Major Workflow
#  8. Test that runs were successful and artifacts were created
#  9. Cleanup repositories
#
  
$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

    $repository = "$githubOwner/$repoName"
    $branch = "main"

    $template = "https://github.com/$githubOwner/$pteTemplate"
    $runs = 0

    if ($adminCenterApiCredentials) {
        $adminCenterApiCredentialsSecret = ConvertTo-SecureString -String $adminCenterApiCredentials -AsPlainText -Force
    }
    
    # Login
    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository

    # Create repo
    CreateRepository -template $template -branch $branch
    $repoPath = (Get-Location).Path

    # Add content
    Copy-Item -Path (Join-Path $PSScriptRoot "content/*") -Destination $repoPath -Recurse -Force
    CommitAndPush -commitMessage "Add content"
    $runs++

    # Update AL-Go System Files
    SetRepositorySecret -name 'GHTOKENWORKFLOW' -value (ConvertTo-SecureString -String $token -AsPlainText -Force)
    Run-UpdateAlGoSystemFiles -templateUrl "$($template)@main" -wait -branch $branch | Out-Null
    $runs++
    MergePRandPull -branch $branch
    $runs++

    # Run CI/CD and wait
    $run = Run-CICD -branch $branch
    $runs++

    # Launch Current, NextMinor and NextMajor builds
    $runTestCurrent = Run-TestCurrent -branch $branch
    SetRepositorySecret -name 'INSIDERSASTOKEN' -value (ConvertTo-SecureString -String $insiderSasToken -AsPlainText -Force)
    $runTestNextMinor = Run-TestNextMinor -branch $branch
    $runTestNextMajor = Run-TestNextMajor -branch $branch

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
    
    RemoveRepository -repository $repository -path $repoPath
}
catch {
    Write-Host $_.Exception.Message
    Write-Host "::Error::$($_.Exception.Message)"
    $host.SetShouldExit(1)
}
finally {
    # Cleanup environments and other stuff
}
