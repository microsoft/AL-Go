Param(
    [switch] $github,
    [string] $githubOwner = "",
    [string] $token = "",
    [string] $template = "",
    [string] $adminCenterApiCredentials = "",
    [string] $licenseFileUrl = "",
    [switch] $multiProject,
    [switch] $appSourceApp
)

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
        $idRange = @{ "from" = 75055000; "to" = 75056000 }
    }
    else {
        $sampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/apps.zip"
        $sampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/testapps.zip"
        if (!$template) { $template = 'al-go-pte' }
        if ($licenseFileUrl) {
            throw "License file secret should not be set"
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
    CreateAndCloneRepository -template $template -branch $branch
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
    if ($appSourceApp) {
        Pull -branch $branch
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
    Test-PropertiesInJsonFile -path "$($project2folder)My App\app.json" -properties @{ "name" = "My App"; "publisher" = "My Publisher"; 'idRanges[0].from' = $idRange.from; "idRanges[0].to" = $idRange.to; 'idRanges.Count' = 1 }

    # Create New Test App
    Run-CreateTestApp @project2Param -name "My TestApp" -publisher "My Publisher" -idrange "58000..59000" -directCommit -wait -branch $branch | Out-Null
    $runs++
    Test-PropertiesInJsonFile -path "$($project2folder)My TestApp\app.json" -properties @{ "name" = "My TestApp"; "publisher" = "My Publisher"; 'idRanges[0].from' = 58000; "idRanges[0].to" = 59000; 'idRanges.Count' = 1 }

    # Create Online Development Environment
    if ($adminCenterApiCredentials -and -not $multiProject) {
        SetRepositorySecret -name 'ADMINCENTERAPICREDENTIALS' -value $adminCenterApiCredentialsSecret
        Run-CreateOnlineDevelopmentEnvironment -environmentName $repoName -directCommit -branch $branch | Out-Null
        $runs++
    }
    else {
        Write-Host "::Warning::No AdminCenterApiCredentials, skipping online dev environment creation"
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
        $repoSettings = Get-Content $_ -Encoding UTF8 | ConvertFrom-Json
        $reposettings | Add-Member -NotePropertyName 'versioningStrategy' -NotePropertyValue 16
        $repoSettings | ConvertTo-Json | Set-Content $_ -Encoding UTF8
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
    if (Test-Path ".gitub\workflows\CreateRelease.yaml") { throw "CreateRelease.yaml should have been removed" }
    $run = Run-CICD -wait -branch $branch
    $runs++
    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 3 -expectedNumberOfTestApps 2 -expectedNumberOfTests 2 -folder 'artifacts3' -repoVersion '3.0.' -appVersion '3.0'

    # Update AL-Go System Files
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

    # TODO: Test Release
    
    # TODO: Test Release notes

    # TODO: Check that environment was created and that launch.json was updated

    # Test localdevenv
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
