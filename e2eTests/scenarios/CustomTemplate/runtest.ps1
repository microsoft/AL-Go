[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global vars used for local test execution only.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'All scenario tests have equal parameter set.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'Secrets are transferred as plain text.')]
Param(
    [switch] $github,
    [switch] $linux,
    [string] $githubOwner = $global:E2EgithubOwner,
    [string] $repoName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()),
    [string] $e2eAppId,
    [string] $e2eAppKey,
    [string] $algoauthapp = ($global:SecureALGOAUTHAPP | Get-PlainText),
    [string] $pteTemplate = $global:pteTemplate,
    [string] $appSourceTemplate = $global:appSourceTemplate,
    [string] $adminCenterApiCredentials = ($global:SecureadminCenterApiCredentials | Get-PlainText),
    [string] $azureCredentials = ($global:SecureAzureCredentials | Get-PlainText),
    [string] $githubPackagesToken = ($global:SecureGitHubPackagesToken | Get-PlainText)
)

Write-Host -ForegroundColor Yellow @'
#   _____          _                    _______                   _       _
#  / ____|        | |                  |__   __|                 | |     | |
# | |    _   _ ___| |_ ___  _ __ ___      | | ___ _ __ ___  _ __ | | __ _| |_ ___
# | |   | | | / __| __/ _ \| '_ ` _ \     | |/ _ \ '_ ` _ \| '_ \| |/ _` | __/ _ \
# | |___| |_| \__ \ || (_) | | | | | |    | |  __/ | | | | | |_) | | (_| | ||  __/
#  \_____\__,_|___/\__\___/|_| |_| |_|    |_|\___|_| |_| |_| .__/|_|\__,_|\__\___|
#                                                          | |
#                                                          |_|
# This test tests the following scenario:
#
#  - Create a new repository based on the PTE template with no apps (this will be the custom template repository)
#  - Create a new repository based on the PTE template with 1 app, using compilerfolder and donotpublishapps (this will be the "final" template repository)
#  - Run Update AL-Go System Files in final repo (using custom template repository as template)
#  - Run Update AL-Go System files in custom template repository
#  - Validate that custom AL-Go files are applied in custom template repository
#  - Validate that custom job is present in custom template repository
#  - Run Update AL-Go System files in final repo
#  - Validate that custom AL-Go files of template repository are applied in final repository
#  - Run Update AL-Go System files in final repo
#  - Validate that custom AL-Go files of template repository and final repository are applied in final repository
#  - Validate that custom job is present in final repo
#
'@

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0
$prevLocation = Get-Location

Remove-Module e2eTestHelper -ErrorAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot "..\..\e2eTestHelper.psm1") -DisableNameChecking
. (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Actions\AL-Go-Helper.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Actions\CheckForUpdates\yamlclass.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath "..\..\..\Actions\CheckForUpdates\CheckForUpdates.HelperFunctions.ps1")

$templateRepository = "$githubOwner/$repoName-template"
$repository = "$githubOwner/$repoName"
$branch = "main"

$template = "https://github.com/$pteTemplate"

# Login
SetTokenAndRepository -github:$github -githubOwner $githubOwner -appId $e2eAppId -appKey $e2eAppKey -repository $repository

#region create repositories

# Create template repository
CreateAlGoRepository `
    -github:$github `
    -linux:$linux `
    -template $template `
    -repository $templateRepository `
    -branch $branch
$templateRepoPath = (Get-Location).Path

# Stop all currently running workflows on template repository
CancelAllWorkflows -repository $templateRepository

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
    -addRepoSettings @{ "useCompilerFolder" = $true; "doNotPublishApps" = $true } `
    -contentScript {
        Param([string] $path)
        $null = CreateNewAppInFolder -folder $path -name $appName -publisher $publisherName
    }
$finalRepoPath = (Get-Location).Path

# Stop all currently running workflows on final repository
CancelAllWorkflows -repository $repository

# Update AL-Go System Files to use template repository
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

# Stop all currently running workflows on final repository
CancelAllWorkflows -repository $repository

#endregion

#region setup template repository customizations

Set-Location $templateRepoPath

Pull

# Make modifications to the template repository

# Add Custom Jobs to CICD.yaml
$cicdWorkflow = Join-Path $templateRepoPath '.github/workflows/CICD.yaml'
$cicdYaml = [yaml]::Load($cicdWorkflow)
$cicdYaml | Should -Not -BeNullOrEmpty

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
        "Origin" = [CustomizationOrigin]::TemplateRepository
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
        "Origin" = [CustomizationOrigin]::TemplateRepository
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
        "Origin" = [CustomizationOrigin]::TemplateRepository
    }
)
# Add custom Jobs
$cicdYaml.AddCustomJobsToYaml($customJobs, [CustomizationOrigin]::FinalRepository) # In the context of the template repository, these custom jobs are treated as final customizations
$cicdYaml.Save($cicdWorkflow)

# Add a custom workflow file in the template repository (to be copied to the final repository, as workflow files are always propagated)
$customWorkflowfileRelativePath = '.github/workflows/CustomWorkflow.yaml'
$customWorkflowFile = Join-Path $templateRepoPath $customWorkflowfileRelativePath
$customWorkflowContent = @"
name: Custom Workflow

on:
  push:
    branches:
      - main

defaults:
  run:
    shell: powershell

jobs:
  CustomJob:
    runs-on: [ windows-latest ]
    steps:
      - name: Checkout
        uses: actions/checkout@v2
      - name: Run Custom Script
        run: |
          Write-Host 'Custom Workflow was triggered!'
"@
Set-Content -Path $customWorkflowFile -Value $customWorkflowContent

$finalRepoCustomWorkflowContent = $customWorkflowContent
if($linux) {
    $finalRepoCustomWorkflowContent = $finalRepoCustomWorkflowContent -replace 'windows-latest', 'ubuntu-latest'
    $finalRepoCustomWorkflowContent = $finalRepoCustomWorkflowContent -replace 'shell: powershell', 'shell: pwsh'
}

# Add custom files in the template repository
$defaultCustomFileName = 'CustomTemplateFile.Default.txt'
$defaultCustomFile = Join-Path $templateRepoPath $defaultCustomFileName
$defaultCustomFileContent = "This is a default custom file in the template repository."
Set-Content -Path $defaultCustomFile -Value $defaultCustomFileContent

$optionalCustomFileName = 'CustomTemplateFile.Optional.txt'
$optionalCustomFile = Join-Path $templateRepoPath $optionalCustomFileName
$optionalCustomFileContent = "This is an optional custom file in the template repository."
Set-Content -Path $optionalCustomFile -Value $optionalCustomFileContent

$legacyCustomFileName = 'CustomTemplateFile.Legacy.txt'

# Remove workflow files from template repository
$excludedWorkflowFileName = 'DeployReferenceDocumentation.yaml'
$excludedWorkflowFileRelativePath = Join-Path '.github/workflows' $excludedWorkflowFileName
$excludedWorkflowFile = Join-Path $templateRepoPath $excludedWorkflowFileRelativePath
Remove-Item -Path $excludedWorkflowFile -Force | Out-Null

$missingWorkflowFileName = 'Troubleshooting.yaml'
$missingWorkflowFileRelativePath = Join-Path '.github/workflows' $missingWorkflowFileName
$missingWorkflowFile = Join-Path $templateRepoPath $missingWorkflowFileRelativePath
Remove-Item -Path $missingWorkflowFile -Force | Out-Null

# Add customALGoFiles settings to the template repository
$null = Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{
    "customALGoFiles" = @{
        "filesToInclude" = @( @{ "filter" = $defaultCustomFileName } )
        "filesToExclude" = @( @{ "sourceFolder" = ".github/workflows"; "filter" = $excludedWorkflowFileName } )
        "filesToRemove"  = @( @{ "filter" = $legacyCustomFileName } )
    }
}

# Push
CommitAndPush -commitMessage 'Add template customizations [skip ci]'

#endregion

#region update template repository with template repository customizations

# Update AL-Go System Files for template repository to update customizations from template repository
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $template -ghTokenWorkflow $algoauthapp -repository $templateRepository -branch $branch | Out-Null

# Stop all currently running workflows on template repository
CancelAllWorkflows -repository $templateRepository

# Pull changes
Pull

# Check that custom workflow file is present
(Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Be $customWorkflowContent.Replace("`r", "").TrimEnd("`n")

# Check that default custom file is present
(Join-Path (Get-Location) $defaultCustomFileName) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $defaultCustomFileName) | Should -Be $defaultCustomFileContent.Replace("`r", "").TrimEnd("`n")
# Check that optional custom file is present
(Join-Path (Get-Location) $optionalCustomFileName) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $optionalCustomFileName) | Should -Be $optionalCustomFileContent.Replace("`r", "").TrimEnd("`n")
# Check that legacy custom file is NOT present
(Join-Path (Get-Location) $legacyCustomFileName) | Should -Not -Exist

# Check that excluded workflow file is NOT present (in template's filesToExclude)
(Join-Path (Get-Location) $excludedWorkflowFileRelativePath) | Should -Not -Exist
# Check that missing workflow file is present (in default filesToExclude)
(Join-Path (Get-Location) $missingWorkflowFileRelativePath) | Should -Exist

# Remove missing workflow files from template repository again
Remove-Item -Path $missingWorkflowFile -Force | Out-Null

# Push
CommitAndPush -commitMessage 'Restore template customizations [skip ci]'

#endregion

#region validate template repository CI/CD workflow

# Run CICD
$run = RunCICD -repository $templateRepository -branch $branch -wait

# Check Custom Jobs
Test-LogContainsFromRun -repository $templateRepository -runid $run.id -jobName 'CustomJob-TemplateInit' -stepName 'Init' -expectedText 'CustomJob-TemplateInit was here!'
Test-LogContainsFromRun -repository $templateRepository -runid $run.id -jobName 'CustomJob-TemplateDeploy' -stepName 'Deploy' -expectedText 'CustomJob-TemplateDeploy was here!'
{ Test-LogContainsFromRun -repository $templateRepository -runid $run.id -jobName 'JustSomeTemplateJob' -stepName 'JustSomeTemplateStep' -expectedText 'JustSomeTemplateJob was here!' } | Should -Throw

#endregion

#region setup final repository customizations

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
        "Origin" = [CustomizationOrigin]::FinalRepository
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
        "Origin" = [CustomizationOrigin]::FinalRepository
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
        "Origin" = [CustomizationOrigin]::FinalRepository
    }
)
# Add custom Jobs
$cicdYaml.AddCustomJobsToYaml($customJobs, [CustomizationOrigin]::FinalRepository)

# save
$cicdYaml.Save($cicdWorkflow)

# Add custom files in the final repository
$legacyCustomFileContent = "This is a removed custom file that will be removed in the final repository."
Set-Content -Path (Join-Path (Get-Location) $legacyCustomFileName) -Value $legacyCustomFileContent

# Remove workflow files from final repository
Remove-Item -Path (Join-Path (Get-Location) $missingWorkflowFileRelativePath) -Force | Out-Null

# Check that custom workflow file is NOT present
(Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Not -Exist

# Check that default custom file is NOT present in final repository
(Join-Path (Get-Location) $defaultCustomFileName) | Should -Not -Exist
# Check that optional custom file is NOT present in final repository
(Join-Path (Get-Location) $optionalCustomFileName) | Should -Not -Exist
# Check that legacy custom file is present in final repository
(Join-Path (Get-Location) $legacyCustomFileName) | Should -Exist

# Check that excluded workflow file is present in final repository
(Join-Path (Get-Location) $excludedWorkflowFileRelativePath) | Should -Exist
# Check that missing workflow file is NOT present in final repository
(Join-Path (Get-Location) $missingWorkflowFileRelativePath) | Should -Not -Exist

# Push
CommitAndPush -commitMessage 'Add final repo customizations [skip ci]'

#endregion

#region update final repository with template repository customizations

# Update AL-Go System Files for the final repository to uptake customizations from template repository
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

# Stop all currently running workflows on final repository
CancelAllWorkflows -repository $repository

# Pull changes
Pull

(Join-Path (Get-Location) $CustomTemplateRepoSettingsFile) | Should -Exist
(Join-Path (Get-Location) $CustomTemplateProjectSettingsFile) | Should -Exist

# Check that custom workflow file is present
(Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Be $finalRepoCustomWorkflowContent.Replace("`r", "").TrimEnd("`n")

# Check that default custom file is present (in template's filesToInclude)
(Join-Path (Get-Location) $defaultCustomFileName) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $defaultCustomFileName) | Should -Be $defaultCustomFileContent.Replace("`r", "").TrimEnd("`n")
# Check that optional custom file is NOT present (not in default or template's filesToInclude)
(Join-Path (Get-Location) $optionalCustomFileName) | Should -Not -Exist
# Check that legacy custom file is NOT present (in template's filesToRemove)
(Join-Path (Get-Location) $legacyCustomFileName) | Should -Not -Exist

# Check that excluded workflow file is NOT present (in default filesToInclude and template's filesToExclude)
(Join-Path (Get-Location) $excludedWorkflowFileRelativePath) | Should -Not -Exist
# Check that missing workflow file is present (in default filesToInclude, propagated from PTE template)
(Join-Path (Get-Location) $missingWorkflowFileRelativePath) | Should -Exist

# Add customALGoFiles settings to the final repository
$null = Add-PropertiesToJsonFile -path '.github/AL-Go-Settings.json' -properties @{
    "customALGoFiles" = @{
        "filesToInclude" = @( @{ "filter" = $optionalCustomFileName } )
        "filesToExclude" = @( @{ "filter" = $defaultCustomFileName } )
    }
}

# Push
CommitAndPush -commitMessage 'Add custom files to be updated when updating AL-Go system files [skip ci]'

#endregion

#region update final repository with template and final repository customizations

# Update AL-Go System Files for final repository to uptake customizations from final repository
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

# Stop all currently running workflows on final repository
CancelAllWorkflows -repository $repository

# Pull changes
Pull

# Check that custom workflow file is present
(Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $customWorkflowfileRelativePath) | Should -Be $finalRepoCustomWorkflowContent.Replace("`r", "").TrimEnd("`n")

 # Check that default custom file is NOT present (in repo's filesToExclude and template's filesToInclude)
(Join-Path (Get-Location) $defaultCustomFileName) | Should -Not -Exist
# Check that optional custom file is present (in repos's filesToInclude)
(Join-Path (Get-Location) $optionalCustomFileName) | Should -Exist
Get-ContentLF -Path (Join-Path (Get-Location) $optionalCustomFileName) | Should -Be $optionalCustomFileContent.Replace("`r", "").TrimEnd("`n")
# Check that legacy custom file is NOT present (in template's filesToRemove)
(Join-Path (Get-Location) $legacyCustomFileName) | Should -Not -Exist

# Check that excluded workflow file is NOT present (in default filesToInclude and template's filesToExclude)
(Join-Path (Get-Location) $excludedWorkflowFileRelativePath) | Should -Not -Exist
# Check that missing workflow file is present (in default filesToInclude, propagated from PTE template)
(Join-Path (Get-Location) $missingWorkflowFileRelativePath) | Should -Exist

#endregion

#region validate final repository CI/CD workflow

# Run CICD
$run = RunCICD -repository $repository -branch $branch -wait

# Check Custom Jobs
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'CustomJob-TemplateInit' -stepName 'Init' -expectedText 'CustomJob-TemplateInit was here!'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'CustomJob-TemplateDeploy' -stepName 'Deploy' -expectedText 'CustomJob-TemplateDeploy was here!'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'CustomJob-PreDeploy' -stepName 'PreDeploy' -expectedText 'CustomJob-PreDeploy was here!'
Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'CustomJob-PostDeploy' -stepName 'PostDeploy' -expectedText 'CustomJob-PostDeploy was here!'
{ Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'JustSomeJob' -stepName 'JustSomeStep' -expectedText 'JustSomeJob was here!' } | Should -Throw
{ Test-LogContainsFromRun -repository $repository -runid $run.id -jobName 'JustSomeTemplateJob' -stepName 'JustSomeTemplateStep' -expectedText 'JustSomeTemplateJob was here!' } | Should -Throw

#endregion

Set-Location $prevLocation

RefreshToken -repository $repository
RemoveRepository -repository $repository -path $finalRepoPath
RefreshToken -repository $templateRepository
RemoveRepository -repository $templateRepository -path $templateRepoPath
