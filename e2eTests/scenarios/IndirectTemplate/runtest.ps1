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
#  - Add CustomStep to indirect repo
#  - Run Update AL-Go System files in indirect repo
#  - Validate that custom step is present in indirect repo
#  - Run Update AL-Go System files in final repo
#  - Validate that custom step is present in final repo
#  - Add CustomStep in final repo
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

# Create repository
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
$repoPath = (Get-Location).Path

# Update AL-Go System Files to uptake UseProjectDependencies setting
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $token -repository $repository -branch $branch | Out-Null

Set-Location $templateRepoPath

Pull

# Make modifications to the template repository
$buildALGoProjectWorkflow = Join-Path $templateRepoPath '.github/workflows/_BuildALGoProject.yaml'
$buildYaml = [yaml]::Load($buildALGoProjectWorkflow)
$buildYaml | Should -Not -BeNullOrEmpty

# Modify the permissions 
$buildYaml.Replace('permissions:/contents: read', @('contents: write', 'issues: read'))

# Add customization steps
$customizationAnchors = GetCustomizationAnchors
$idx = 0
foreach($anchor in $customizationAnchors.'_BuildALGoProject.yaml'.BuildALGoProject) {
    $idx++
    $customStep = @{
        "Name" = "CustomStep-Template$idx"
        "Content" = @(
            "- name: CustomStep-Template$idx"
            "  run: |"
            "    Write-Host 'CustomStep-Template$idx was here!'"
        )
        "AnchorStep" = $anchor.Step
        "Before" = $anchor.Before
    }
    $buildYaml.AddCustomStepsToAnchor('BuildALGoProject', $customStep, $anchor.Step, $anchor.Before)
}
$buildYaml.Save($buildALGoProjectWorkflow)

# Add Custom Jobs to CICD.yaml
$cicdWorkflow = Join-Path $templateRepoPath '.github/workflows/CICD.yaml'
$cicdYaml = [yaml]::Load($cicdWorkflow)
$cicdYaml | Should -Not -BeNullOrEmpty
# Modify the permissions 
$cicdYaml.Replace('permissions:/contents: read', @('contents: write', 'issues: read'))
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
)
# Add custom Jobs
$cicdYaml.AddCustomJobsToYaml($customJobs)
$cicdYaml.Save($cicdWorkflow)

# Push
CommitAndPush -commitMessage 'Add template customizations'

# Do not run workflows on template repository
CancelAllWorkflows -repository $templateRepository

# Add local customizations to the final repository
Set-Location $repoPath
Pull

# Make modifications to the template repository
$buildALGoProjectWorkflow = Join-Path $repoPath '.github/workflows/_BuildALGoProject.yaml'
$buildYaml = [yaml]::Load($buildALGoProjectWorkflow)
$buildYaml | Should -Not -BeNullOrEmpty

# Add customization steps
$customizationAnchors = GetCustomizationAnchors
$idx = 0
foreach($anchor in $customizationAnchors.'_BuildALGoProject.yaml'.BuildALGoProject) {
    $idx++
    $customStep = @{
        "Name" = "CustomStep-Final$idx"
        "Content" = @(
            "- name: CustomStep-Final$idx"
            "  run: |"
            "    Write-Host 'CustomStep-Final$idx was here!'"
        )
        "AnchorStep" = $anchor.Step
        "Before" = $anchor.Before
    }
    $buildYaml.AddCustomStepsToAnchor('BuildALGoProject', $customStep, $anchor.Step, $anchor.Before)
}

# save
$buildYaml.Save($buildALGoProjectWorkflow)

# Add Custom Jobs to CICD.yaml
$cicdWorkflow = Join-Path $repoPath '.github/workflows/CICD.yaml'
$cicdYaml = [yaml]::Load($cicdWorkflow)
$cicdYaml | Should -Not -BeNullOrEmpty
# Modify the permissions 
$cicdYaml.Replace('permissions:/contents: read', @('contents: read', 'issues: write'))

$customJobs = @(
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

# Run CICD
$run = RunCICD -repository $repository -branch $branch -wait

# Check Custom Steps
1..$idx | ForEach-Object {
    Test-LogContainsFromRun -runid $run.id -jobName 'Build . (Default)  . (Default)' -stepName "CustomStep-Template$_" -expectedText "CustomStep-Template$_ was here!"
}
1..$idx | ForEach-Object {
    Test-LogContainsFromRun -runid $run.id -jobName 'Build . (Default)  . (Default)' -stepName "CustomStep-Final$_" -expectedText "CustomStep-Final$_ was here!"
}

# Check correct order of custom steps
DownloadWorkflowLog -repository $repository -runid $run.id -path 'logs'
$logcontent = Get-Content -Path 'logs/0_Build . (Default)  . (Default).txt' -Encoding utf8 -Raw
Remove-Item -Path 'logs' -Recurse -Force
$idx = 0
foreach($anchor in $customizationAnchors.'_BuildALGoProject.yaml'.BuildALGoProject) {
    $idx++
    $templateStepIdx = $logcontent.IndexOf("CustomStep-Template$idx was here!")
    $finalStepIdx = $logcontent.IndexOf("CustomStep-Final$idx was here!")
    if ($anchor.Before) {
        $finalStepIdx | Should -BeGreaterThan $templateStepIdx -Because "CustomStep-Final$idx should be after CustomStep-Template$idx"
    }
    else {
        $finalStepIdx | Should -BeLessThan $templateStepIdx -Because "CustomStep-Final$idx should be before CustomStep-Template$idx"
    }
}

# Check Custom Jobs
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-TemplateInit' -stepName 'Init' -expectedText 'CustomJob-TemplateInit was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-TemplateDeploy' -stepName 'Deploy' -expectedText 'CustomJob-TemplateDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-PreDeploy' -stepName 'PreDeploy' -expectedText 'CustomJob-PreDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-PostDeploy' -stepName 'PostDeploy' -expectedText 'CustomJob-PostDeploy was here!'

# Check Permissions
# TODO: check issues: write in cicd.yaml (from final) and issues: read in _buildALGoProject.yaml (from template)
$buildALGoProjectWorkflow = Join-Path $repoPath '.github/workflows/_BuildALGoProject.yaml'
$buildYaml = [yaml]::Load($buildALGoProjectWorkflow)
$buildYaml | Should -Not -BeNullOrEmpty
$buildYaml.get('Permissions:/issues:').content | Should -Be 'issues: read'

$cicdWorkflow = Join-Path $repoPath '.github/workflows/CICD.yaml'
$cicdYaml = [yaml]::Load($cicdWorkflow)
$cicdYaml | Should -Not -BeNullOrEmpty
$cicdYaml.get('Permissions:/issues:').content | Should -Be 'issues: write'

Set-Location $prevLocation

Read-Host "Press Enter to continue"

RemoveRepository -repository $repository -path $repoPath
RemoveRepository -repository $templateRepository -path $templateRepoPath
