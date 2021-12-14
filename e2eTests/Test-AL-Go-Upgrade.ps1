Param(
    [switch] $github,
    [string] $githubOwner = "",
    [string] $token = "",
    [string] $path = "",
    [string] $release = "",
    [string] $template = "",
    [string] $licenseFileUrl = "",
    [switch] $appSourceApp,
    [switch] $private
)

#  ______           _ ___                _    _    _                           _         _           _                                    _       
# |  ____|         | |__ \              | |  | |  | |                         | |       | |         | |                                  (_)      
# | |__   _ __   __| |  ) |___ _ __   __| |  | |  | |_ __   __ _ _ __ __ _  __| | ___   | |_ ___ ___| |_    ___  ___ ___ _ __   __ _ _ __ _  ___  
# |  __| | '_ \ / _` | / // _ \ '_ \ / _` |  | |  | | '_ \ / _` | '__/ _` |/ _` |/ _ \  | __/ _ \ __| __|  / __|/ __/ _ \ '_ \ / _` | '__| |/ _ \ 
# | |____| | | | (_| |/ /_  __/ | | | (_| |  | |__| | |_) | (_| | | | (_| | (_| |  __/  | |_  __\__ \ |_   \__ \ (__  __/ | | | (_| | |  | | (_) |
# |______|_| |_|\__,_|____\___|_| |_|\__,_|   \____/| .__/ \__, |_|  \__,_|\__,_|\___|   \__\___|___/\__|  |___/\___\___|_| |_|\__,_|_|  |_|\___/ 
#                                                   | |     __/ |                                                                                 
#                                                   |_|    |___/                                                                                  
#
# This scenario runs for every previously released version of GitHub Go - both for PTEs and AppSource Apps
# The scenario tests that we do not break existing CI/CD workflows and that existing repositories can upgrade to newest version
#
#  1. Login
#  2. Create a new repository based on the selected template and the selected version
#  3. If (AppSource App) Create a licensefileurl secret
#  4. Run CI/CD workflow
#  5.  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
#  6. Create the GHTOKENWORKFLOW secret
#  7. Run the "Update AL-Go System Files" workflow as a Pull Request
#  8.  Test that a Pull Request was created and merge the Pull Request
#  9. Run CI/CD workflow
# 10.  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
# 11.  Test number of workflows ran is correct
# 12. Cleanup
#

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

    if (!$github) {
        if (!$token) {  $token = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "OrgPAT").SecretValue | Get-PlainText }
        $githubOwner = "freddydk"
        if (!$licenseFileUrl -and $appSourceApp) { $licenseFileUrl = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "licenseFile").SecretValue | Get-PlainText }
        $release = "v0.1"
        if ($appSourceApp) {
            $path = "appsourceapp"
        }
        else {
            $path = "pte"
        }
    }

    $reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
    $repository = "$githubOwner/$repoName"
    $branch = "main"

    if ($appSourceApp) {
        $orgTemplate = 'https://github.com/microsoft/al-go-appSource'
        if (!$licenseFileUrl) {
            throw "License file secret must be set"
        }
    }
    else {
        $orgTemplate = 'https://github.com/microsoft/al-go-pte'
        if ($licenseFileUrl) {
            throw "License file secret should not be set"
        }
    }
    $template = "https://github.com/$githubOwner/$template"
    $runs = 0

    # Login
    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository -github:$github

    # Create repo
    CreateRepository -template $orgTemplate -templateBranch $release -templatePath (Join-Path $PSScriptRoot $path) -branch $branch -private:$private
    $repoPath = (Get-Location).Path

    # Add AppFolders and TestFolders
    $settingsFile = Join-Path $repoPath '.AL-Go\settings.json'
    $settings = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
    $settings.appFolders += "My App"
    $settings.testFolders += "My App.Test"
    if ($appSourceApp) {
        $settings.AppSourceCopMandatoryAffixes = @("cust")
    }
    $settings | ConvertTo-Json | Set-Content $settingsFile -Encoding UTF8
    Add-Content -path (Join-Path $repoPath '.AL-Go\localdevenv.ps1') -Encoding UTF8 -Value "`n`n# Dummy comment" |
    CommitAndPush -commitMessage "Update settings.json"
    $runs++

    # Add Existing App
    if ($appSourceApp) {
        SetRepositorySecret -name 'LICENSEFILEURL' -value (ConvertTo-SecureString -String $licenseFileUrl -AsPlainText -Force)
    }

    # Run CI/CD and wait
    $run = Run-CICD -wait -branch $branch
    $runs++
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 1 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0.' -appVersion ''

    # Update AL-Go System Files
    SetRepositorySecret -name 'GHTOKENWORKFLOW' -value (ConvertTo-SecureString -String $token -AsPlainText -Force)
    Run-UpdateAlGoSystemFiles -templateUrl $template -wait -branch $branch | Out-Null
    $runs++
    MergePRandPull -branch $branch
    $runs += 2

    # Run CI/CD and wait
    $run = Run-CICD -wait -branch $branch
    $runs++
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 1 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts2' -repoVersion '1.0.' -appVersion ''
    
    Test-NumberOfRuns -expectedNumberOfRuns $runs
    
    RemoveRepository -repository $repository -path $repoPath
}
catch {
    Write-Host $_.Exception.Message
    Write-Host "::Error::$($_.Exception.Message)"
    if ($github) {
        $host.SetShouldExit(1)
    }
}
