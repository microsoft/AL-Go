[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
Param(
    [switch] $github,
    [switch] $linux,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $e2epat = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $algoauthapp = ($Global:SecureALGOAUTHAPP | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#  _____       __                               _____                                        _        _   _
# |  __ \     / _|                             |  __ \                                      | |      | | (_)
# | |__) |___| |_ ___ _ __ ___ _ __   ___ ___  | |  | | ___   ___ _   _ _ __ ___   ___ _ __ | |_ __ _| |_ _  ___  _ __
# |  _  // _ \  _/ _ \ '__/ _ \ '_ \ / __/ _ \ | |  | |/ _ \ / __| | | | '_ ` _ \ / _ \ '_ \| __/ _` | __| |/ _ \| '_ \
# | | \ \  __/ ||  __/ | |  __/ | | | (_|  __/ | |__| | (_) | (__| |_| | | | | | |  __/ | | | || (_| | |_| | (_) | | | |
# |_|  \_\___|_| \___|_|  \___|_| |_|\___\___| |_____/ \___/ \___|\__,_|_| |_| |_|\___|_| |_|\__\__,_|\__|_|\___/|_| |_|
#
#
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with 1 app
#  - Enable GitHub pages (set to GitHub Actions)
#  - Run the "CI/CD" workflow
#  - Run the Deploy Reference Documentation workflow
#  - Check github pages website generated
#  - Change settings to use continuous deployment of ALDoc and modify the header
#  - Run the "CI/CD" workflow
#  - Check that the new header is used
#  - Set runs-on to ubuntu-latest (and use CompilerFolder)
#  - Modify the header again
#  - Run the "CI/CD" workflow again
#  - Check that the new header is used
#  - Cleanup repositories
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
Push-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking

$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $e2epat -repository $repository

$appName = 'MyApp'
$publisherName = 'Freddy'

# Create repository1
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -contentScript {
        Param([string] $path)
        $null = CreateNewAppInFolder -folder $path -name $appName -publisher $publisherName
        Add-PropertiesToJsonFile -path (Join-Path $path '.github/AL-Go-Settings.json') -properties @{ "alDoc" = @{ "ContinuousDeployment" = $true; "deployToGitHubPages" = $false } }
    }

# Cancel all running workflows
CancelAllWorkflows -repository $repository

$repoPath = (Get-Location).Path
$run = RunCICD -repository $repository -branch $branch

# Wait for CI/CD workflow of repository1 to finish
WaitWorkflow -repository $repository -runid $run.id

# test artifacts generated in repository1
Test-ArtifactsFromRun -runid $run.id -folder 'artifacts' -expectedArtifacts @{"Apps"=1;"TestApps"=0;"Dependencies"=0;"github-pages"=1} -repoVersion '1.0' -appVersion '1.0'

# Set GitHub Pages in repository to GitHub Actions
gh api --method POST /repos/$repository/pages -f build_type=workflow | Out-Null

# Add setting to deploy to GitHub Pages
Pull
Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "alDoc" = @{ "ContinuousDeployment" = $false; "deployToGitHubPages" = $true } }
CommitAndPush -commitMessage 'DeployToGitHubPages'

# Run Deploy Reference Documentation and wait for it to finish
RunDeployReferenceDocumentation -repository $repository -wait | Out-Null

# Get Pages URL and read the content
$pagesInfo = gh api /repos/$repository/pages | ConvertFrom-Json
$html = (Invoke-WebRequest -Uri $pagesInfo.html_url -UseBasicParsing).Content
$html | Should -belike "*Documentation for $repository*"

# Remove downloaded artifacts
Remove-Item -Path 'artifacts' -Recurse -Force

# Set continuous deployment of ALDoc and modify the header
Pull
Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{ "alDoc" = @{ "ContinuousDeployment" = $true; "deployToGitHubPages" = $true; "Header" = "Documentazione per {REPOSITORY}" } }
CommitAndPush -commitMessage 'Continuous Deployment of ALDoc'

# Wait for CI/CD run after config change
WaitAllWorkflows -repository $repository -noError

# Get Pages URL and read the content
$pagesInfo = gh api /repos/$repository/pages | ConvertFrom-Json
$html = (Invoke-WebRequest -Uri $pagesInfo.html_url -UseBasicParsing).Content
$html | Should -belike "*Documentazione per $repository*"

Pop-Location

RemoveRepository -repository $repository -path $repoPath
