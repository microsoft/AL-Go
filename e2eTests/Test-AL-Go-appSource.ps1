Param(
    [switch] $gitHub,
    [string] $githubOwner = "",
    [string] $token = "",
    [string] $template = "",
    [string] $adminCenterApiCredentials = "",
    [string] $licenseFileUrl = "",
    [switch] $multiProject
)

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

Write-Host -ForegroundColor Yellow @'
_______       _              _           _____                                                             _                       _       _       
|__   __|     | |       /\   | |         / ____|                                                           | |                     | |     | |      
   | | ___ ___| |_     /  \  | |  ______| |  __  ___ ______ __ _ _ __  _ __  ___  ___  _   _ _ __ ___ ___  | |_ ___ _ __ ___  _ __ | | __ _| |_ ___ 
   | |/ _ \ __| __|   / /\ \ | | |______| | |_ |/ _ \______/ _` | '_ \| '_ \/ __|/ _ \| | | | '__/ __/ _ \ | __/ _ \ '_ ` _ \| '_ \| |/ _` | __/ _ \
   | |  __\__ \ |_   / ____ \| |____    | |__| | (_) |    | (_| | |_) | |_) \__ \ (_) | |_| | | | (__  __/ | |_  __/ | | | | | |_) | | (_| | |_  __/
   |_|\___|___/\__| /_/    \_\______|    \_____|\___/      \__,_| .__/| .__/|___/\___/ \__,_|_|  \___\___|  \__\___|_| |_| |_| .__/|_|\__,_|\__\___|
                                                                | |   | |                                                    | |                    
                                                                |_|   |_|                                                    |_|                    
'@

$reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
$repository = "$githubOwner/$repoName"
$sampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-appsource-preview/2.0.47.0/apps.zip"
$sampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-appsource-preview/2.0.47.0/testapps.zip"
$branch = "main"
$projectParam = @{}
$projectFolder = ""

try {
    Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

    if ($github) {
        $template = "https://github.com/$githubOwner/$template"
    }
    else {
        if (!$token) {  $token = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "OrgPAT").SecretValue | Get-PlainText }
        if (!$template) { $template = 'https://github.com/freddydk/al-go-appSource' }
        if (!$adminCenterApiCredentials) { $adminCenterApiCredentials = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "adminCenterApiCredentials").SecretValue | Get-PlainText }
        if (!$licenseFileUrl) { $licenseFileUrl = (Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "licenseFile").SecretValue | Get-PlainText }
    }

    if ($adminCenterApiCredentials) {
        $adminCenterApiCredentialsSecret = ConvertTo-SecureString -String $adminCenterApiCredentials -AsPlainText -Force
    }

    if ($licenseFileUrl -eq '') {
        throw "License file secret not set"
    }

    SetTokenAndRepository -githubOwner $githubOwner -token $token -repository $repository -github:$github

    CreateAndCloneRepository -template $template -branch $branch
    $repoPath = (Get-Location).Path

    SetRepositorySecret -name 'LICENSEFILEURL' -value (ConvertTo-SecureString -String $licenseFileUrl -AsPlainText -Force)

    if ($multiProject) {
        $projectParam = @{ "project" = "P1" }
        $projectFolder = 'P1\'
    }

    Run-AddExistingAppOrTestApp @projectParam -url $sampleApp1 -wait -directCommit -branch $branch | Out-Null

    Pull -branch $branch
    
    Add-PropertiesToJsonFile -jsonFile "$($projectFolder).AL-Go\settings.json" -properties @{ "AppSourceCopMandatoryAffixes" = @( "hw_", "cus" ) }

    Run-AddExistingAppOrTestApp @projectParam -url $sampleTestApp1 -wait -branch $branch | Out-Null

    MergePRandPull -branch $branch

    $run = Run-CICD -wait -branch $branch

    Test-NumberOfRuns -expectedNumberOfRuns 5

    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 2 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0.' -appVersion ''
    
    Run-CreateRelease -appVersion '1.0.3.0' -name '1.0' -tag '1.0' -wait -branch $branch | Out-Null

    if ($multiProject) {
        $projectParam = @{ "project" = "P2" }
        $projectFolder = 'P2\'
    }

    Run-CreateApp @projectParam -name "My App" -publisher "My Publisher" -idrange "75055000..75056000" -directCommit -wait -branch $branch | Out-Null

    Pull -branch $branch

    Copy-Item -path "Default App Name\logo\helloworld256x240.png" -Destination "My App\helloworld256x240.png"
    Add-PropertiesToJsonFile -jsonFile "$($projectFolder)My App\app.json" -properties @{
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

    # Test-AppJson -path "My App\app.json" -properties @{ "name" = "My ApP"; "publisher" = "My Publisher" }

    Run-CreateTestApp @projectParam -name "My TestApp" -publisher "My Publisher" -idrange "75058000..75059000" -directCommit -wait -branch $branch | Out-Null

    # Test-AppJson -path "My TestApp\app.json" -properties @{ "name" = "My ApP"; "publisher" = "My Publisher" }

    if ($adminCenterApiCredentials -and -not $multiProject) {
        SetRepositorySecret -name 'ADMINCENTERAPICREDENTIALS' -value $adminCenterApiCredentialsSecret
        Run-CreateOnlineDevelopmentEnvironment -environmentName $repoName -directCommit -branch $branch | Out-Null
    }
    else {
        Write-Host "::Warning::No AdminCenterApiCredentials, skipping online dev environment creation"
    }

    Run-IncrementVersionNumber @projectParam -versionNumber 2.0 -wait -branch $branch | Out-Null

    MergePRandPull -branch $branch

    $run = Run-CICD -wait -branch $branch

    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 3 -expectedNumberOfTestApps 2 -expectedNumberOfTests 2 -folder 'artifacts2' -repoVersion '2.0.' -appVersion ''

    $repoSettings = Get-Content ".AL-Go\settings.json" -Encoding UTF8 | ConvertFrom-Json
    $reposettings | Add-Member -NotePropertyName 'versioningStrategy' -NotePropertyValue 16
    $repoSettings | ConvertTo-Json | Set-Content ".AL-Go\settings.json" -Encoding UTF8
    Remove-Item -Path ".AL-Go\*.ps1" -Force
    Remove-Item -Path ".github\workflows\CreateRelease.yaml" -Force

    CommitAndPush -commitMessage "Version strategy change"

    if ($multiProject) {
        $projectParam = @{
            "project" = "*"
        }
    }
    Run-IncrementVersionNumber @projectParam -versionNumber 3.0 -directCommit -wait -branch $branch | Out-Null

    Pull -branch $branch

    if (Test-Path ".AL-Go\*.ps1") { throw "Local PowerShell scripts in the .AL-Go folder should have been removed" }
    if (Test-Path ".gitub\workflows\CreateRelease.yaml") { throw "CreateRelease.yaml should have been removed" }

    $run = Run-CICD -wait -branch $branch

    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 3 -expectedNumberOfTestApps 2 -expectedNumberOfTests 2 -folder 'artifacts3' -repoVersion '3.0.' -appVersion '3.0'

    SetRepositorySecret -name 'GHTOKENWORKFLOW' -value (ConvertTo-SecureString -String $token -AsPlainText -Force)

    Run-UpdateAlGoSystemFiles -templateUrl $repoSettings.templateUrl -wait -branch $branch | Out-Null
    MergePRandPull -branch $branch

    if (!(Test-Path ".AL-Go\*.ps1")) { throw "Local PowerShell scripts in the .AL-Go folder was not updated by Update AL-Go System Files" }
    if (!(Test-Path ".github\workflows\CreateRelease.yaml")) { throw "CreateRelease.yaml was not updated by Update AL-Go System Files" }

    Run-CreateRelease -appVersion latest -name "v3.0" -tag "v3.0" -wait -branch $branch | Out-Null

    # Test Release
    
    # Test Release notes

    # Check that environment was created and that launch.json was updated

    # Test localdevenv

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
