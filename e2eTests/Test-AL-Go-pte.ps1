Param(
    [string] $actor = "",
    [string] $token = ((Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "OrgPAT").SecretValue | Get-PlainText),
    [string] $template = 'https://github.com/microsoft/al-go-pte',
    [string] $adminCenterApiCredentials = ((Get-AzKeyVaultSecret -VaultName "BuildVariables" -Name "adminCenterApiCredentials").SecretValue | Get-PlainText)
)

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "e2eTestHelper.psm1") -DisableNameChecking

$adminCenterApiCredentialsSecret = ConvertTo-SecureString -String $adminCenterApiCredentials -AsPlainText -Force

$reponame = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName())
$repository = "freddydk/$repoName"

SetTokenAndRepository -actor $actor -token $token -repository $repository

Write-Host -ForegroundColor Yellow @'
  _______       _              _           _____                   _          _                       _       _       
 |__   __|     | |       /\   | |         / ____|                 | |        | |                     | |     | |      
    | | ___ ___| |_     /  \  | |  ______| |  __  ___ ______ _ __ | |_ ___   | |_ ___ _ __ ___  _ __ | | __ _| |_ ___ 
    | |/ _ \ __| __|   / /\ \ | | |______| | |_ |/ _ \______| '_ \| __/ _ \  | __/ _ \ '_ ` _ \| '_ \| |/ _` | __/ _ \
    | |  __\__ \ |_   / ____ \| |____    | |__| | (_) |     | |_) | |_  __/  | |_  __/ | | | | | |_) | | (_| | |_  __/
    |_|\___|___/\__| /_/    \_\______|    \_____|\___/      | .__/ \__\___|   \__\___|_| |_| |_| .__/|_|\__,_|\__\___|
                                                            | |                                | |                    
                                                            |_|                                |_|                    
'@

$pteSampleApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/apps.zip"
$pteSampleTestApp1 = "https://businesscentralapps.blob.core.windows.net/githubhelloworld-preview/2.0.82.0/testapps.zip"
$branch = "main"

$path = CreateAndCloneRepository -template $template -branch $branch

try {
    Run-AddExistingAppOrTestApp -url $pteSampleApp1 -wait -branch $branch | Out-Null

    MergePRandPull -branch $branch

    Run-AddExistingAppOrTestApp -url $pteSampleTestApp1 -directCommit -wait -branch $branch | Out-Null

    $run = Run-CICD -wait -branch $branch

    Test-NumberOfRuns -expectedNumberOfRuns 4

    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 2 -expectedNumberOfTestApps 1 -expectedNumberOfTests 1 -folder 'artifacts' -repoVersion '1.0.' -appVersion ''
    
    Run-CreateRelease -appVersion '1.0.2.0' -name '1.0' -tag '1.0' -wait -branch $branch | Out-Null

    Run-CreateApp -name "My App" -publisher "My Publisher" -idrange "55000..56000" -directCommit -wait -branch $branch | Out-Null

    # Test-AppJson -path "My App\app.json" -properties @{ "name" = "My ApP"; "publisher" = "My Publisher" }

    Run-CreateTestApp -name "My TestApp" -publisher "My Publisher" -idrange "58000..59000" -directCommit -wait -branch $branch | Out-Null

    # Test-AppJson -path "My TestApp\app.json" -properties @{ "name" = "My ApP"; "publisher" = "My Publisher" }

    SetRepositorySecret -name 'ADMINCENTERAPICREDENTIALS' -value $adminCenterApiCredentialsSecret

    Run-CreateOnlineDevelopmentEnvironment -environmentName $repoName -directCommit -branch $branch | Out-Null

    Run-IncrementVersionNumber -versionNumber 2.0 -wait -branch $branch | Out-Null

    MergePRandPull -branch $branch

    $run = Run-CICD -wait -branch $branch

    Test-ArtifactsFromRun -runid $run.id -expectedNumberOfApps 3 -expectedNumberOfTestApps 2 -expectedNumberOfTests 2 -folder 'artifacts2' -repoVersion '2.0.' -appVersion ''

    $repoSettings = Get-Content ".AL-Go\settings.json" -Encoding UTF8 | ConvertFrom-Json
    $reposettings | Add-Member -NotePropertyName 'versioningStrategy' -NotePropertyValue 16
    $repoSettings | ConvertTo-Json | Set-Content ".AL-Go\settings.json" -Encoding UTF8
    Remove-Item -Path ".AL-Go\*.ps1" -Force
    Remove-Item -Path ".github\workflows\CreateRelease.yaml" -Force

    CommitAndPush -commitMessage "Version strategy change"

    Run-IncrementVersionNumber -versionNumber 3.0 -directCommit -wait -branch $branch | Out-Null

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

}
catch {
    Write-Host $_.Exception.Message
}
finally {
    try {    
        #RemoveRepository -token $token -repository $repository -path $path
        $params = $adminCenterApiCredentialsSecret.SecretValue | Get-PlainText | ConvertFrom-Json | ConvertTo-HashTable
        $authContext = New-BcAuthContext @params
        Remove-BcEnvironment -bcAuthContext $authContext -environment $reponame -doNotWait
    }
    catch {}
}
