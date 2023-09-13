[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
Param(
    [switch] $github,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText),
    [string] $licenseFileUrl = ($global:SecureLicenseFileUrl | Get-PlainText),
    [string] $insiderSasToken = ($global:SecureInsiderSasToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#  _____            _           _      _____                            _                 _
# |_   _|          | |         | |    |  __ \                          | |               (_)
#   | |  _ __   ___| |_   _  __| | ___| |  | | ___ _ __   ___ _ __   __| | ___ _ __   ___ _  ___  ___
#   | | | '_ \ / __| | | | |/ _` |/ _ \ |  | |/ _ \ '_ \ / _ \ '_ \ / _` |/ _ \ '_ \ / __| |/ _ \/ __|
#  _| |_| | | | (__| | |_| | (_| |  __/ |__| |  __/ |_) |  __/ | | | (_| |  __/ | | | (__| |  __/\__ \
# |_____|_| |_|\___|_|\__,_|\__,_|\___|_____/ \___| .__/ \___|_| |_|\__,_|\___|_| |_|\___|_|\___||___/
#                                                 | |
#                                                 |_|                                                 #
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template, running Windows with 5 projects, using appDependencyProbingPaths with release_status set to 'include'
#    - P1/app1 with dependency to P1/app2
#    - P1/app2 with no dependencies
#    - P2/app3 with dependency to P1/app1 and P1/app2
#    - P3/app4 with dependency to P1/app1
#    - P4/app5 with dependency to P3/app4 and P2/app3
#    - P0/app6 with dependency to P3/app4 and P2/app3
#  - Run the "CI/CD" workflow
#  - Run the Test Current Workflow
#  - Run the Test Next Minor Workflow
#  - Run the Test Next Major Workflow
#  - Test that runs were successful and artifacts were created in CI/CD workflow
#  - Redo everything on Linux
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location
$repoPath = ""

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create repo
CreateAlGoRepository `
    -github:$github `
    -template $template `
    -repository $repository `
    -branch $branch `
    -projects @('P1','P2','P3','P4','P0') `
    -contentScript {
        Param([string] $path)
        $id2 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name app2 -objID 50002
        $id1 = CreateNewAppInFolder -folder (Join-Path $path 'P1') -name app1 -objID 50001 -dependencies @( @{ "id" = $id2; "name" = "app2"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
        Add-PropertiesToJsonFile -path (Join-Path $path 'P1\.AL-Go\settings.json') -properties @{ "country" = "w1" }
        $id3 = CreateNewAppInFolder -folder (Join-Path $path 'P2') -name app3 -objID 50003 -dependencies @( @{ "id" = $id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }, @{ "id" = $id2; "name" = "app2"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
        Add-PropertiesToJsonFile -path (Join-Path $path 'P2\.AL-Go\settings.json') -properties @{ "country" = "w1"; "appDependencyProbingPaths" = @( @{ "repo" = "."; "release_status" = "include"; "projects" = "P1" } ) }
        $id4 = CreateNewAppInFolder -folder (Join-Path $path 'P3') -name app4 -objID 50004 -dependencies @( @{ "id" = $id1; "name" = "app1"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
        Add-PropertiesToJsonFile -path (Join-Path $path 'P3\.AL-Go\settings.json') -properties @{ "country" = "w1"; "appDependencyProbingPaths" = @( @{ "repo" = "."; "release_status" = "include"; "projects" = "P1" } ) }
        $null = CreateNewAppInFolder -folder (Join-Path $path 'P4') -name app5 -objID 50005 -dependencies @( @{ "id" = $id4; "name" = "app4"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }; @{ "id" = $id3; "name" = "app3"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
        Add-PropertiesToJsonFile -path (Join-Path $path 'P4\.AL-Go\settings.json') -properties @{ "country" = "it"; "appDependencyProbingPaths" = @( @{ "repo" = "."; "release_status" = "include"; "projects" = "P2,P3" } ) }
        $null = CreateNewAppInFolder -folder (Join-Path $path 'P0') -name app6 -objID 50006 -dependencies @( @{ "id" = $id4; "name" = "app4"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" }; @{ "id" = $id3; "name" = "app3"; "publisher" = (GetDefaultPublisher); "version" = "1.0.0.0" } )
        Add-PropertiesToJsonFile -path (Join-Path $path 'P0\.AL-Go\settings.json') -properties @{ "country" = "dk"; "appDependencyProbingPaths" = @( @{ "repo" = "."; "release_status" = "include"; "projects" = "P3,P2" } ) }
    }

$repoPath = (Get-Location).Path

1..2 | ForEach-Object {
    # Run CI/CD workflow
    $run = RunCICD -branch $branch

    # Launch Current, NextMinor and NextMajor builds
    $runTestCurrent = RunTestCurrent -branch $branch
    $runTestNextMinor = RunTestNextMinor -branch $branch -insiderSasToken $insiderSasToken
    $runTestNextMajor = RunTestNextMajor -branch $branch -insiderSasToken $insiderSasToken

    # Wait for CI/CD workflow to finish
    WaitWorkflow -runid $run.id
    # P0 has 5 apps: app1,app2,app3,app4 and app6
    # P1 has 2 apps: app1,app2
    # P2 has 3 apps: app1,app2,app3
    # P3 has 3 apps: app1,app2,app4
    # P4 has 5 apps: app1,app2,app3,app4,app5
    Test-ArtifactsFromRun -runid $run.id -folder "artifacts$_" -expectedArtifacts @{"Apps"=(5+2+3+3+5);"thisbuild"=0} -repoVersion '1.0' -appVersion '1.0'

    WaitWorkflow -runid $runTestCurrent.id -noDelay
    WaitWorkflow -runid $runTestNextMinor.id -noDelay
    WaitWorkflow -runid $runTestNextMajor.id -noDelay

    if ($_ -eq 1) {
        # Pull latest changes
        Pull

        # Set GitHubRunner and runs-on to ubuntu-latest (and use CompilerFolder)
        Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "runs-on" = "ubuntu-latest"; "gitHubRunner" = "ubuntu-latest"; "UseCompilerFolder" = $true; "doNotPublishApps" = $true }

        # Push
        CommitAndPush -commitMessage 'Shift to Linux'

        # Upgrade AL-Go System Files
        RunUpdateAlGoSystemFiles -directCommit -commitMessage 'Update system files' -wait -templateUrl $template
    }
}

Set-Location $prevLocation

RemoveRepository -repository $repository -path $repoPath
