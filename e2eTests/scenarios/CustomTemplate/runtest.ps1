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
#  - Validate that custom job is present in custom template repository
#  - Run Update AL-Go System files in final repo
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
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

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
$cicdYaml.AddCustomJobsToYaml($customJobs, [CustomizationOrigin]::TemplateRepository)
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


# Push
CommitAndPush -commitMessage 'Add final repo customizations'

# Update AL-Go System Files to uptake UseProjectDependencies setting
RunUpdateAlGoSystemFiles -directCommit -wait -templateUrl $templateRepository -ghTokenWorkflow $algoauthapp -repository $repository -branch $branch | Out-Null

# Stop all currently running workflows and run a new CI/CD workflow
CancelAllWorkflows -repository $repository

# Pull changes
Pull

(Join-Path (Get-Location) $CustomTemplateRepoSettingsFile) | Should -Exist
(Join-Path (Get-Location) $CustomTemplateProjectSettingsFile) | Should -Exist

# Run CICD
$run = RunCICD -repository $repository -branch $branch -wait

# Check Custom Jobs
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-TemplateInit' -stepName 'Init' -expectedText 'CustomJob-TemplateInit was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-TemplateDeploy' -stepName 'Deploy' -expectedText 'CustomJob-TemplateDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-PreDeploy' -stepName 'PreDeploy' -expectedText 'CustomJob-PreDeploy was here!'
Test-LogContainsFromRun -runid $run.id -jobName 'CustomJob-PostDeploy' -stepName 'PostDeploy' -expectedText 'CustomJob-PostDeploy was here!'
{ Test-LogContainsFromRun -runid $run.id -jobName 'JustSomeJob' -stepName 'JustSomeStep' -expectedText 'JustSomeJob was here!' } | Should -Throw
{ Test-LogContainsFromRun -runid $run.id -jobName 'JustSomeTemplateJob' -stepName 'JustSomeTemplateStep' -expectedText 'JustSomeTemplateJob was here!' } | Should -Throw

Set-Location $prevLocation

RemoveRepository -repository $repository -path $finalRepoPath
RemoveRepository -repository $templateRepository -path $templateRepoPath
