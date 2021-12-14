Param(
    [switch] $github,
    [string] $githubOwner = "",
    [string] $token = "",
    [string] $template = "",
    [string] $adminCenterApiCredentials = "",
    [string] $licenseFileUrl = "",
    [string] $insiderSasToken = "",
    [switch] $multiProject,
    [switch] $appSourceApp,
    [switch] $private
)

#  ______           _ ___                _    _           _                                    _       
# |  ____|         | |__ \              | |  | |         | |                                  (_)      
# | |__   _ __   __| |  ) |___ _ __   __| |  | |_ ___ ___| |_    ___  ___ ___ _ __   __ _ _ __ _  ___  
# |  __| | '_ \ / _` | / // _ \ '_ \ / _` |  | __/ _ \ __| __|  / __|/ __/ _ \ '_ \ / _` | '__| |/ _ \ 
# | |____| | | | (_| |/ /_  __/ | | | (_| |  | |_  __\__ \ |_   \__ \ (__  __/ | | | (_| | |  | | (_) |
# |______|_| |_|\__,_|____\___|_| |_|\__,_|   \__\___|___/\__|  |___/\___\___|_| |_|\__,_|_|  |_|\___/ 
#
# This scenario runs for both PTE template and AppSource App template and as single project and multi project repositories
#                                                                                                      
#  1. Login to GitHub
#  2. Create a new repository based on the selected template
#  3. If (AppSource App) Create a licensefileurl secret
#  4. Run the "Add an existing app" workflow and add an app as a Pull Request
#  5.  Test that a Pull Request was created and merge the Pull Request
#  6. Run the "CI/CD" workflow
#  7.  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
#  8. Run the "Create Release" workflow to create a version 1.0 release
#  9. Run the "Create a new App" workflow to add a new app (adjust necessary properties if multiproject or appsource app)
# 10.  Test that app.json exists and properties in app.json are as expected
# 11. Run the "Create a new Test App" workflow to add a new test app
# 12.  Test that app.json exists and properties in app.json are as expected
# 13. Run the "Create Online Development Environment" if requested
# 14. Run the "Increment version number" workflow for one project (not changing apps) as a Pull Request
# 15.  Test that a Pull Request was created and merge the Pull Request
# 16. Run the CI/CD workflow
# 17.  Test that the number of workflows ran is correct and the artifacts created from CI/CD are correct and of the right version
# 18. Modify repository versioning strategy and remove some scripts + a .yaml file
# 19. Run the CI/CD workflow
# 20.  Test that artifacts created from CI/CD are correct and of the right version (also apps version numbers should be updated)
# 21. Create the GHTOKENWORKFLOW secret
# 22. Run the "Update AL-Go System Files" workflow as a Pull Request
# 23.  Test that a Pull Request was created and merge the Pull Request
# 24.  Test that the previously deleted files are now updated
# 25. Run the "Create Release" workflow
# 26. Run the Test Current Workflow
# 27. Run the Test Next Minor Workflow
# 28. Run the Test Next Major Workflow
#
# TODO: some more tests to do here
#
# 29.  Test that the number of workflows ran is correct.
# 30. Cleanup repositories
#
  
$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

    if (!$github) {
        if (!$token) {  $token = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "OrgPAT").SecretValue | Get-PlainText }
        $githubOwner = "freddydk"
        if (!$adminCenterApiCredentials) { $adminCenterApiCredentials = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "adminCenterApiCredentials").SecretValue | Get-PlainText }
        if (!$licenseFileUrl) { $licenseFileUrl = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "licenseFile").SecretValue | Get-PlainText }
        if (!$insiderSasToken) { $insiderSasToken = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "insiderSasToken").SecretValue | Get-PlainText }
    }

    $reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
    $repository = "$githubOwner/$repoName"
    $branch = "main"
    
    if ($appSourceApp) {
        $sampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-appsource-preview/2.0.47.0/apps.zip"
        $sampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-appsource-preview/2.0.47.0/testapps.zip"
        if (!$template) { $template = 'al-go-appSource' }
        if (!$licenseFileUrl) {
            throw "License file secret must be set"
        }
        if ($adminCenterApiCredentials) {
            throw "adminCenterApiCredentials should not be set"
        }
        $idRange = @{ "from" = 75055000; "to" = 75056000 }
    }
    else {
        $sampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/apps.zip"
        $sampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/testapps.zip"
        if (!$template) { $template = 'al-go-pte' }
        if ($licenseFileUrl) {
            throw "License file secret should not be set"
        }
        if ($multiProject) {
            if ($adminCenterApiCredentials) {
                throw "adminCenterApiCredentials should not be set"
            }
        }
        else {
            if (-not $adminCenterApiCredentials) {
                throw "adminCenterApiCredentials should be set"
            }
        }
        $idRange = @{ "from" = 55000; "to" = 56000 }
    }
    if ($multiProject) {
        $project1Param = @{ "project" = "P1" }
        $project1Folder = 'P1\'
        $project2Param = @{ "project" = "P2" }
        $project2Folder = 'P2\'
        $allProjectsParam = @{ "project" = "*" }
        $projectSettingsFiles = @("P1\.AL-Go\Settings.json", "P2\.AL-Go\Settings.json")
    }
    else {
        $project1Param = @{}
        $project1Folder = ""
        $project2Param = @{}
        $project2Folder = ""
        $allProjectsParam = @{}
        $projectSettingsFiles = @(".AL-Go\Settings.json")
    }

    $template = "https://github.com/$githubOwner/$template"
    $runs = 0

    if ($adminCenterApiCredentials) {
        $adminCenterApiCredentialsSecret = ConvertTo-SecureString -String $adminCenterApiCredentials -AsPlainText -Force
    }
    
    # Login
    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository -github:$github

    # Create repo
    CreateRepository -template $template -branch $branch -private:$private
    $repoPath = (Get-Location).Path

    # Add Existing App
    if ($appSourceApp) {
        SetRepositorySecret -name 'LICENSEFILEURL' -value (ConvertTo-SecureString -String $licenseFileUrl -AsPlainText -Force)
    }
    Run-AddExistingAppOrTestApp @project1Param -url $sampleApp1 -wait -directCommit -branch $branch | Out-Null
    $runs++
    if ($appSourceApp) {
        Pull -branch $branch
        Add-PropertiesToJsonFile -jsonFile "$($project1Folder).AL-Go\settings.json" -properties @{ "AppSourceCopMandatoryAffixes" = @( "hw_", "cus" ) }
        $runs++
    }

    # Add Existing Test App
    Run-AddExistingAppOrTestApp @project1Param -url $sampleTestApp1 -wait -branch $branch | Out-Null
    $runs++
    MergePRandPull -branch $branch
    $runs++

    # Run CI/CD and wait
    $run = Run-CICD -wait -branch $branch
    $runs++

    Test-NumberOfRuns -expectedNumberOfRuns $runs
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 2 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0.' -appVersion ''
    
    # Create Release
    Run-CreateRelease -appVersion "1.0.$($runs-2).0" -name '1.0' -tag '1.0' -wait -branch $branch | Out-Null
    $runs++

    # Create New App
    Run-CreateApp @project2Param -name "My App" -publisher "My Publisher" -idrange "$($idRange.from)..$($idRange.to)" -directCommit -wait -branch $branch | Out-Null
    $runs++
    Pull -branch $branch
    if ($appSourceApp) {
        if ($multiProject) {
            Add-PropertiesToJsonFile -jsonFile "$($project2Folder).AL-Go\settings.json" -properties @{ "AppSourceCopMandatoryAffixes" = @( "cus" ) }
            $runs++
        }
        Copy-Item -path "$($project1Folder)Default App Name\logo\helloworld256x240.png" -Destination "$($project2Folder)My App\helloworld256x240.png"
        Add-PropertiesToJsonFile -jsonFile "$($project2Folder)My App\app.json" -properties @{
            "brief" = "Hello World for AppSource"
            "description" = "Hello World sample app for AppSource"
            "logo" = "helloworld256x240.png"
            "url" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
            "EULA" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
            "privacyStatement" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
            "help" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
            "contextSensitiveHelpUrl" = "https://dev.azure.com/businesscentralapps/HelloWorld.AppSource"
            "features" = @( "TranslationFile" )
        }
        $runs++
    }
    Test-PropertiesInJsonFile -jsonFile "$($project2folder)My App\app.json" -properties @{ "name" = "My App"; "publisher" = "My Publisher"; 'idRanges[0].from' = $idRange.from; "idRanges[0].to" = $idRange.to; 'idRanges.Count' = 1 }

    # Create New Test App
    Run-CreateTestApp @project2Param -name "My TestApp" -publisher "My Publisher" -idrange "58000..59000" -directCommit -wait -branch $branch | Out-Null
    $runs++
    Pull -branch $branch
    Test-PropertiesInJsonFile -jsonFile "$($project2folder)My TestApp\app.json" -properties @{ "name" = "My TestApp"; "publisher" = "My Publisher"; 'idRanges[0].from' = 58000; "idRanges[0].to" = 59000; 'idRanges.Count' = 1 }

    # Create Online Development Environment
    if ($adminCenterApiCredentials -and -not $multiProject) {
        SetRepositorySecret -name 'ADMINCENTERAPICREDENTIALS' -value $adminCenterApiCredentialsSecret
        Run-CreateOnlineDevelopmentEnvironment -environmentName $repoName -directCommit -branch $branch | Out-Null
        $runs++
    }

    # Increment version number on one project
    Run-IncrementVersionNumber @project2Param -versionNumber 2.0 -wait -branch $branch | Out-Null
    $runs++
    MergePRandPull -branch $branch
    $runs++
    $run = Run-CICD -wait -branch $branch
    $runs++
    if ($multiProject) {
        Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 1 -expectedNumberOfTestApps 1 -expectedNumberOfTests 2 -folder 'artifacts2' -repoVersion '2.0.' -appVersion ''
    }
    else {
        Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 3 -expectedNumberOfTestApps 2 -expectedNumberOfTests 2 -folder 'artifacts2' -repoVersion '2.0.' -appVersion ''
    }
    Test-NumberOfRuns -expectedNumberOfRuns $runs

    # Modify versioning strategy
    $projectSettingsFiles | ForEach-Object {
        $projectSettings = Get-Content $_ -Encoding UTF8 | ConvertFrom-Json
        $projectsettings | Add-Member -NotePropertyName 'versioningStrategy' -NotePropertyValue 16
        $projectSettings | ConvertTo-Json | Set-Content $_ -Encoding UTF8
    }
    Remove-Item -Path "$($project1Folder).AL-Go\*.ps1" -Force
    Remove-Item -Path ".github\workflows\CreateRelease.yaml" -Force
    CommitAndPush -commitMessage "Version strategy change"
    $runs++

    # Increment version number on all project (and on all apps)
    Run-IncrementVersionNumber @allProjectsParam -versionNumber 3.0 -directCommit -wait -branch $branch | Out-Null
    $runs++
    Pull -branch $branch
    if (Test-Path "$($project1Folder).AL-Go\*.ps1") { throw "Local PowerShell scripts in the .AL-Go folder should have been removed" }
    if (Test-Path ".github\workflows\CreateRelease.yaml") { throw "CreateRelease.yaml should have been removed" }
    $run = Run-CICD -wait -branch $branch
    $runs++
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 3 -expectedNumberOfTestApps 2 -expectedNumberOfTests 2 -folder 'artifacts3' -repoVersion '3.0.' -appVersion '3.0'

    # Update AL-Go System Files
    $repoSettings = Get-Content ".github\AL-Go-Settings.json" -Encoding UTF8 | ConvertFrom-Json
    SetRepositorySecret -name 'GHTOKENWORKFLOW' -value (ConvertTo-SecureString -String $token -AsPlainText -Force)
    Run-UpdateAlGoSystemFiles -templateUrl $repoSettings.templateUrl -wait -branch $branch | Out-Null
    $runs++
    MergePRandPull -branch $branch
    $runs += 2
    if (!(Test-Path "$($project1Folder).AL-Go\*.ps1")) { throw "Local PowerShell scripts in the .AL-Go folder was not updated by Update AL-Go System Files" }
    if (!(Test-Path ".github\workflows\CreateRelease.yaml")) { throw "CreateRelease.yaml was not updated by Update AL-Go System Files" }

    # Create Release
    Run-CreateRelease -appVersion latest -name "v3.0" -tag "v3.0" -wait -branch $branch | Out-Null
    $runs++

    # Launch Current, NextMinor and NextMajor builds
    $runTestCurrent = Run-TestCurrent -branch $branch
    SetRepositorySecret -name 'INSIDERSASTOKEN' -value (ConvertTo-SecureString -String $insiderSasToken -AsPlainText -Force)
    $runTestNextMinor = Run-TestNextMinor -branch $branch
    $runTestNextMajor = Run-TestNextMajor -branch $branch

    # TODO: Test workspace
    
    # TODO: Test Release
    
    # TODO: Test Release notes

    # TODO: Check that environment was created and that launch.json was updated

    # Test localdevenv

    WaitWorkflow -runid $runTestNextMajor.id
    $runs++

    WaitWorkflow -runid $runTestNextMinor.id
    $runs++

    WaitWorkflow -runid $runTestCurrent.id
    $runs++

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
finally {
    try {
        $params = $adminCenterApiCredentialsSecret.SecretValue | Get-PlainText | ConvertFrom-Json | ConvertTo-HashTable
        $authContext = New-BcAuthContext @params
        Remove-BcEnvironment -bcAuthContext $authContext -environment $reponame -doNotWait
    }
    catch {}
}
