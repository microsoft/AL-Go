[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
Param(
    [switch] $github,
    [switch] $linux,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $token = ($Global:SecureE2EPAT | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiToken = ($global:SecureAdminCenterApiToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#  _____           _ _               _     _______                   _       _
# |_   _|         | (_)             | |   |__   __|                 | |     | |
#   | |  _ __   __| |_ _ __ ___  ___| |_     | | ___ _ __ ___  _ __ | | __ _| |_ ___
#   | | | '_ \ / _` | | '__/ _ \/ __| __|    | |/ _ \ '_ ` _ \| '_ \| |/ _` | __/ _ \
#  _| |_| | | | (_| | | | |  __/ (__| |_     | |  __/ | | | | | |_) | | (_| | ||  __/
# |_____|_| |_|\__,_|_|_|  \___|\___|\__|    |_|\___|_| |_| |_| .__/|_|\__,_|\__\___|
#                                                             | |
#                                                             |_|
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with no apps (this will be the "indirect" template repository)
#  - Create a new repository based on the PTE template with 1 app, using compilerfolder and donotpublishapps (this will be the "final" template repository)
#  - Run Update AL-Go System Files in final repo (using indirect repo as template)
#  - Run Update AL-Go System files in indirect repo

# TODO: describe the scenario


#  - Validate that custom step is present in indirect repo
#  - Run Update AL-Go System files in final repo
#  - Validate that custom step is present in final repo
#  - Run Update AL-Go System files in final repo
#  - Validate that both custom steps is present in final repo
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking
. (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Actions\CheckForUpdates\yamlclass.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\..\Actions\CheckForUpdates\CheckForUpdates.HelperFunctions.ps1")

$templateRepository = "$githubOwner/$repoName-template"
$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -token $token -repository $repository

# Create tempolate repository
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $templateRepository `
    -branch $branch
$templateRepoPath = (Get-Location).Path

Set-Location $prevLocation

$appName = 'MyApp'
$publisherName = 'Contoso'

# Create final repository
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $repository `
    -branch $branch `
    -contentScript {
        Param([string] $path)
        $null = CreateNewAppInFolder -folder $path -name $appName -publisher $publisherName
    }
$finalRepoPath = (Get-Location).Path

# Update AL-Go System Files to use template repository
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $token -repository $repository -branch $branch | Out-Null

Set-Location $templateRepoPath

Pull

# Make modifications to the template repository

# Add Custom Jobs to CICD.yaml
$cicdWorkflow = Join-Path $templateRepoPath '.github/workflows/CICD.yaml'
$cicdYaml = [yaml]::Load($cicdWorkflow)
$cicdYaml | Should -Not -BeNullOrEmpty

# Modify the permissions
$customJobs = @(
    @{
        "Name" = "CustomJob-TemplateInit"
        "Content" = @(
            "CustomJob-TemplateInit:"
            "  runs-on: [ windows-latest ]"
            "  steps:"
            "    - name: Init"
            "      run: |"
            "        Write-Host 'CustomJob-TemplateInit was here!'"
        )
        "NeedsThis" = @( 'Initialization' )
    }
    @{
        "Name" = "CustomJob-TemplateDeploy"
        "Content" = @(
            "CustomJob-TemplateDeploy:"
            "  needs: [ Initialization, Build ]"
            "  runs-on: [ windows-latest ]"
            "  steps:"
            "    - name: Deploy"
            "      run: |"
            "        Write-Host 'CustomJob-TemplateDeploy was here!'"
        )
        "NeedsThis" = @( 'PostProcess' )
    }
    @{
        "Name" = "JustSomeTemplateJob"
        "Content" = @(
            "JustSomeTemplateJob:"
            "  needs: [ PostProcess ]"
            "  runs-on: [ windows-latest ]"
            "  steps:"
            "    - name: JustSomeTemplateStep"
            "      run: |"
            "        Write-Host 'JustSomeTemplateJob was here!'"
        )
        "NeedsThis" = @( )
    }
)
# Add custom Jobs
$cicdYaml.AddCustomJobsToYaml($customJobs)
$cicdYaml.Save($cicdWorkflow)

# Push
CommitAndPush -commitMessage 'Add template customizations'

# Do not run workflows on template repository
CancelAllWorkflows -repository $templateRepository

# Add local customizations to the final repository
Set-Location $finalRepoPath
Pull

# Make modifications to the final repository

# Add Custom Jobs to CICD.yaml
$cicdWorkflow = Join-Path $finalRepoPath '.github/workflows/CICD.yaml'
$cicdYaml = [yaml]::Load($cicdWorkflow)
$cicdYaml | Should -Not -BeNullOrEmpty

$customJobs = @(
    @{
        "Name" = "JustSomeJob"
        "Content" = @(
            "JustSomeJob:"
            "  needs: [ Initialization ]"
            "  runs-on: [ windows-latest ]"
            "  steps:"
            "    - name: JustSomeStep"
            "      run: |"
            "        Write-Host 'JustSomeJob was here!'"
        )
        "NeedsThis" = @( 'Build' )
    }
    @{
        "Name" = "CustomJob-PreDeploy"
        "Content" = @(
            "CustomJob-PreDeploy:"
            "  needs: [ Initialization, Build ]"
            "  runs-on: [ windows-latest ]"
            "  steps:"
            "    - name: PreDeploy"
            "      run: |"
            "        Write-Host 'CustomJob-PreDeploy was here!'"
        )
        "NeedsThis" = @( 'Deploy' )
    }
    @{
        "Name" = "CustomJob-PostDeploy"
        "Content" = @(
            "CustomJob-PostDeploy:"
            "  needs: [ Initialization, Build, Deploy ]"
            "  if: (!cancelled())"
            "  runs-on: [ windows-latest ]"
            "  steps:"
            "    - name: PostDeploy"
            "      run: |"
            "        Write-Host 'CustomJob-PostDeploy was here!'"
        )
        "NeedsThis" = @( 'PostProcess' )
    }
)
# Add custom Jobs
$cicdYaml.AddCustomJobsToYaml($customJobs)

# save
$cicdYaml.Save($cicdWorkflow)


# Push
CommitAndPush -commitMessage 'Add final repo customizations'

# Update AL-Go System Files to uptake UseProjectDependencies setting
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $token -repository $repository -branch $branch | Out-Null

# Stop all currently running workflows and run a new CI/CD workflow
CancelAllWorkflows -repository $repository

# Pull changes
Pull

# TODO: Check that the settings from the indirect template repository was copied to $IndirectTemplateRepoSettingsFile and $IndirectTemplateProjectSettingsFile

# Run CICD
$run = RunCICD -repository $repository -branch $branch -wait

# Check Custom Jobs
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-TemplateInit' -stepName 'Init' -expectedText 'CustomJob-TemplateInit was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-TemplateDeploy' -stepName 'Deploy' -expectedText 'CustomJob-TemplateDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-PreDeploy' -stepName 'PreDeploy' -expectedText 'CustomJob-PreDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-PostDeploy' -stepName 'PostDeploy' -expectedText 'CustomJob-PostDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'JustSomeJob' -stepName 'JustSomeStep' -expectedText 'JustSomeJob was here!' | Should -Throw
Test-LogContainsFromRun -runid $run.id -jobName 'JustSomeTemplateJob' -stepName 'JustSomeTemplateStep' -expectedText 'JustSomeTemplateJob was here!' | Should -Throw

Set-Location $prevLocation

# TODO: Modify settings in the template repository and re-run Update AL-Go System Files in the final repository to check that the settings are copied to the final repository

# TODO: Add tests for CustomALGoSystemFiles (with and without security)

Read-Host "Press Enter to continue"

RemoveRepository -repository $repository -path $finalRepoPath
RemoveRepository -repository $templateRepository -path $templateRepoPath
