Param(
    [switch] $github,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $contentPath = "pte",
    [string] $release = "v2.2",
    [string] $template = $global:pteTemplate,
    [string] $licenseFileUrl = "",
    [switch] $appSourceApp,
    [switch] $private
)

Write-Host -ForegroundColor Yellow @'
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
# - Login
# - Create a new repository based on the selected template and the selected version
# - If (AppSource App) Create a licensefileurl secret
# - Run CI/CD workflow
# -  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
# - Create the GHTOKENWORKFLOW secret
# - Run the "Update AL-Go System Files" workflow as a Pull Request
# -  Test that a Pull Request was created and merge the Pull Request
# - Run CI/CD workflow
# -  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
# -  Test number of workflows ran is correct
# - Cleanup
#
'@

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0
$prevLocation = Get-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

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
$template = "https://github.com/$template"
$runs = 0

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create repo
CreateAlGoRepository -github:$github -template "$($orgTemplate)@$($release)" -contentPath (Join-Path $PSScriptRoot $contentPath) -branch $branch -private:$private
$repoPath = (Get-Location).Path

# Add AppFolders and TestFolders
$settingsFile = Join-Path $repoPath '.AL-Go\settings.json'
$settings = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
$settings.appFolders += "My App"
$settings.testFolders += "My App.Test"
if ($appSourceApp) {
    $settings.AppSourceCopMandatoryAffixes = @("cust")
}
$settings | Set-JsonContentLF -path $settingsFile
Add-Content -path (Join-Path $repoPath '.AL-Go\localdevenv.ps1') -Encoding UTF8 -Value "`n`n# Dummy comment" |
CommitAndPush -commitMessage "Update settings.json"
$runs++

# Add Existing App
if ($appSourceApp) {
    SetRepositorySecret -repository $repository -name 'LICENSEFILEURL' -value $licenseFileUrl
}

# Run CI/CD and wait
$run = Run-CICD -wait -branch $branch
$runs++
Test-ArtifactsFromRun -runid $run.id -expectedArtifacts @{"Apps"=1;"TestApps"=1} -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0' -appVersion ''

# Update AL-Go System Files
SetRepositorySecret -repository $repository -name 'GHTOKENWORKFLOW' -value $token
Run-UpdateAlGoSystemFiles -templateUrl $template -wait -branch $branch | Out-Null
$runs++

# Wait for PR handler to start
Start-Sleep -seconds 100
MergePRandPull -branch $branch
$runs++
if ([System.Version]$release.Substring(1) -ge [System.Version]"2.2") {
    $runs++
}

# Run CI/CD and wait
$run = Run-CICD -wait -branch $branch
$runs++
Test-ArtifactsFromRun -runid $run.id -expectedArtifacts @{"Apps"=1;"TestApps"=1} -expectedNumberOfTests 1 -folder 'artifacts2' -repoVersion '1.0' -appVersion ''

Test-NumberOfRuns -expectedNumberOfRuns $runs -repository $repository

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
