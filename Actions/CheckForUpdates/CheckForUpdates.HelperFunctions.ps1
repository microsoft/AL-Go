<#
.SYNOPSIS
Downloads a template repository and returns the path to the downloaded folder
.PARAMETER token
The GitHub token / PAT to use for authentication (if the template repository is private/internal)
.PARAMETER templateUrl
The URL to the template repository
.PARAMETER templateSha
The SHA of the template repository (returned by reference if downloadLatest is true)
.PARAMETER downloadLatest
If true, the latest SHA of the template repository will be downloaded
#>
function DownloadTemplateRepository {
    Param(
        [string] $token,
        [string] $templateUrl,
        [ref] $templateSha,
        [bool] $downloadLatest
    )

    $templateRepositoryUrl = $templateUrl.Split('@')[0]
    $templateRepository = $templateRepositoryUrl.Split('/')[-2..-1] -join '/'

    # Use Authenticated API request if possible to avoid the 60 API calls per hour limit
    OutputDebug -message "Getting template repository ($templateRepository) with GITHUB_TOKEN"
    $headers = GetHeaders -token $env:GITHUB_TOKEN -repository $templateRepository
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Method Head -Uri $templateRepositoryUrl
        OutputDebug -message ($response | Format-List | Out-String)
    }
    catch {
        # Ignore error
        OutputDebug -message "Error getting template repository with GITHUB_TOKEN:"
        OutputDebug -message $_
        $response = $null
    }
    if (-not $response -or $response.StatusCode -ne 200) {
        # GITHUB_TOKEN doesn't have access to template repository, must be private/internal
        # Get token with read permissions for the template repository
        # NOTE that the GitHub app needs to be installed in the template repository for this to work
        $headers = GetHeaders -token $token -repository $templateRepository
    }

    # Construct API URL
    $apiUrl = $templateUrl.Split('@')[0] -replace "^(https:\/\/github\.com\/)(.*)$", "$ENV:GITHUB_API_URL/repos/`$2"

    Write-Host "TemplateUrl: $templateUrl"
    Write-Host "TemplateSha: $($templateSha.Value)"
    Write-Host "DownloadLatest: $downloadLatest"

    if ($downloadLatest) {
        # Get latest commit SHA from the template repository
        $templateSha.Value = GetLatestTemplateSha -headers $headers -apiUrl $apiUrl -templateUrl $templateUrl
        Write-Host "Latest SHA for $($templateUrl): $($templateSha.Value)"
    }
    $archiveUrl = "$apiUrl/zipball/$($templateSha.Value)"
    Write-Host "Using ArchiveUrl: $archiveUrl"

    # Download template repository
    $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    InvokeWebRequest -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip"
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"
    return $tempName
}

function GetLatestTemplateSha {
    Param(
        [hashtable] $headers,
        [string] $apiUrl,
        [string] $templateUrl
    )

    $branch = $templateUrl.Split('@')[1]
    Write-Host "Get latest SHA for $templateUrl"
    try {
        $branchInfo = (InvokeWebRequest -Headers $headers -Uri "$apiUrl/branches/$branch").Content | ConvertFrom-Json
    } catch {
        throw "Failed to update AL-Go System Files. Could not get the latest SHA from template ($templateUrl). (Error was $($_.Exception.Message))"
    }
    return $branchInfo.commit.sha
}

function ModifyCICDWorkflow {
    Param(
        [Yaml] $yaml,
        [hashtable] $repoSettings
    )

    # The CICD workflow can have a RepoSetting called CICDPushBranches, which will be used to set the branches for the workflow
    # Setting the CICDSchedule will disable the push trigger for the CI/CD workflow (unless CICDPushBranches is set)
    if ($repoSettings.Keys -contains 'CICDPushBranches') {
        $CICDPushBranches = $repoSettings.CICDPushBranches
    }
    elseif ($repoSettings.Keys -contains $workflowScheduleKey) {
        $CICDPushBranches = ''
    }
    else {
        $CICDPushBranches = $defaultCICDPushBranches
    }
    # update the branches: line with the new branches
    if ($CICDPushBranches) {
        $yaml.Replace('on:/push:/branches:', "branches: [ '$($CICDPushBranches -join "', '")' ]")
    }
    else {
        $yaml.Replace('on:/push:',@())
    }
}

function ModifyPullRequestHandlerWorkflow {
    Param(
        [Yaml] $yaml,
        [hashtable] $repoSettings
    )
    # The PullRequestHandler workflow can have a RepoSetting called pullRequestTrigger which specifies the trigger to use for Pull Requests
    $triggerSection = $yaml.Get('on:/pull')
    $triggerSection.content = "$($repoSettings.pullRequestTrigger):"
    $yaml.Replace('on:/pull', $triggerSection.Content)

    # The PullRequestHandler workflow can have a RepoSetting called CICDPullRequestBranches, which will be used to set the branches for the workflow
    if ($repoSettings.Keys -contains 'CICDPullRequestBranches') {
        $CICDPullRequestBranches = $repoSettings.CICDPullRequestBranches
    }
    else {
        $CICDPullRequestBranches = $defaultCICDPullRequestBranches
    }

    # update the branches: line with the new branches
    $yaml.Replace("on:/$($repoSettings.pullRequestTrigger):/branches:", "branches: [ '$($CICDPullRequestBranches -join "', '")' ]")
}

function ModifyRunsOnAndShell {
    Param(
        [Yaml] $yaml,
        [hashtable] $repoSettings
    )

    # The default for runs-on is windows-latest and the default for shell is powershell
    # The default for GitHubRunner/GitHubRunnerShell is runs-on/shell (unless Ubuntu-latest are selected here, as build jobs cannot run on Ubuntu)
    # We do not change runs-on in Update AL-Go System Files and Pull Request Handler workflows
    # These workflows will always run on windows-latest (or maybe Ubuntu-latest later) and not follow settings
    # Reasons:
    # - Update AL-Go System files is needed for changing runs-on - by having non-functioning runners, you might dead-lock yourself
    # - Pull Request Handler workflow for security reasons
    if ($repoSettings."runs-on" -ne "windows-latest") {
        Write-Host "Setting runs-on to [ $($repoSettings."runs-on") ]"
        $yaml.ReplaceAll('runs-on: [ windows-latest ]', "runs-on: [ $($repoSettings."runs-on") ]")
    }
    if ($repoSettings.shell -ne "powershell" -and $repoSettings.shell -ne "pwsh") {
        throw "The shell can only be set to powershell or pwsh"
    }
    if ($repoSettings."runs-on" -eq "ubuntu-latest" -and $repoSettings.shell -eq "powershell") {
        throw "The shell cannot be set to powershell when runs-on is ubuntu-latest. Use pwsh instead."
    }
    Write-Host "Setting shell to $($repoSettings.shell)"
    $yaml.ReplaceAll('shell: powershell', "shell: $($repoSettings.shell)")
}

function ModifyBuildWorkflows {
    Param(
        [Yaml] $yaml,
        [int] $depth,
        [bool] $includeBuildPP
    )

    $yaml.Replace('env:/workflowDepth:',"workflowDepth: $depth")
    $build = $yaml.Get('jobs:/Build:/')
    $buildPP = $yaml.Get('jobs:/BuildPP:/')
    $deliver = $yaml.Get('jobs:/Deliver:/')
    $deploy = $yaml.Get('jobs:/Deploy:/')
    $deployALDoc = $yaml.Get('jobs:/DeployALDoc:/')
    $codeAnalysisUpload = $yaml.Get('jobs:/CodeAnalysisUpload:/')
    $postProcess = $yaml.Get('jobs:/PostProcess:/')
    if (!$build) {
        throw "No build job found in the workflow"
    }

    # Duplicate the build job for each dependency depth
    $newBuild = @()
    for($index = 0; $index -lt $depth; $index++) {
        # All build job needs to have a dependency on the Initialization job
        $needs = @('Initialization')
        if ($index -eq 0) {
            # First build job needs to have a dependency on the Initialization job only
            # Example (depth 1):
            #    needs: [ Initialization ]
            #    if: (!failure()) && (!cancelled()) && fromJson(needs.Initialization.outputs.buildOrderJson)[0].projectsCount > 0
            $if = "if: (!failure()) && (!cancelled()) && fromJson(needs.Initialization.outputs.buildOrderJson)[$index].projectsCount > 0"
        }
        else {
            # Subsequent build jobs needs to have a dependency on all previous build jobs
            # Example (depth 2):
            #    needs: [ Initialization, Build1 ]
            #    if: (!failure()) && (!cancelled()) && (needs.Build1.result == 'success' || needs.Build1.result == 'skipped') && fromJson(needs.Initialization.outputs.buildOrderJson)[0].projectsCount > 0
            # Another example (depth 3):
            #    needs: [ Initialization, Build2, Build1 ]
            #    if: (!failure()) && (!cancelled()) && (needs.Build2.result == 'success' || needs.Build2.result == 'skipped') && (needs.Build1.result == 'success' || needs.Build1.result == 'skipped') && fromJson(needs.Initialization.outputs.buildOrderJson)[0].projectsCount > 0
            $newBuild += @('')
            $ifpart = ""
            $index..1 | ForEach-Object {
                $needs += @("Build$_")
                $ifpart += " && (needs.Build$_.result == 'success' || needs.Build$_.result == 'skipped')"
            }
            $if = "if: (!failure()) && (!cancelled())$ifpart && fromJson(needs.Initialization.outputs.buildOrderJson)[$index].projectsCount > 0"
        }

        # Replace the if:, the needs: and the strategy/matrix/project: in the build job with the correct values
        $build.Replace('if:', $if)
        $build.Replace('needs:', "needs: [ $($needs -join ', ') ]")
        $build.Replace('strategy:/matrix:/include:',"include: `${{ fromJson(needs.Initialization.outputs.buildOrderJson)[$index].buildDimensions }}")

        # Last build job is called build, all other build jobs are called build1, build2, etc.
        if ($depth -eq ($index + 1)) {
            $newBuild += @("Build:")
        }
        else {
            $newBuild += @("Build$($index + 1):")
        }

        # Add the content of the calculated build job to the new build job list with an indentation of 2 spaces
        $build.content | ForEach-Object { $newBuild += @("  $_") }
    }

    # Replace the entire build: job with the new build job list
    $yaml.Replace('jobs:/Build:', $newBuild)

    if (!$includeBuildPP -and $buildPP) {
        # Remove the BuildPP job from the workflow
        [int]$start = 0
        [int]$count = 0
        if ($yaml.Find('jobs:/BuildPP:', [ref] $start, [ref] $count)) {
            $yaml.Remove($start, $count+1)
        }
    }

    $needs += @("Build")
    $ifpart += " && (needs.Build.result == 'success' || needs.Build.result == 'skipped')"
    if ($includeBuildPP -and $buildPP) {
        $needs += @("BuildPP")
        $ifpart += " && (needs.BuildPP.result == 'success' || needs.BuildPP.result == 'skipped')"
    }

    $postProcessNeeds = $needs
    # Modify Deliver and Deploy steps depending on build jobs
    if ($deploy) {
        $deploy.Replace('needs:', "needs: [ $($needs -join ', ') ]")
        $deploy.Replace('if:', "if: (!cancelled())$ifpart && fromJson(needs.Initialization.outputs.deploymentEnvironmentsJson).environmentCount > 0")
        $yaml.Replace('jobs:/Deploy:/', $deploy.content)
        $postProcessNeeds += @('Deploy')
    }
    if ($deliver) {
        $deliver.Replace('needs:', "needs: [ $($needs -join ', ') ]")
        $deliver.Replace('if:', "if: (!cancelled())$ifpart && needs.Initialization.outputs.deliveryTargetsJson != '[]'")
        $yaml.Replace('jobs:/Deliver:/', $deliver.content)
        $postProcessNeeds += @('Deliver')
    }
    if ($deployALDoc) {
        $postProcessNeeds += @('DeployALDoc')
    }
    if ($codeAnalysisUpload) {
        $postProcessNeeds += @('CodeAnalysisUpload')
    }
    if ($postProcess) {
        $postProcess.Replace('needs:', "needs: [ $($postProcessNeeds -join ', ') ]")
        $yaml.Replace('jobs:/PostProcess:/', $postProcess.content)
    }
}

function ModifyUpdateALGoSystemFiles {
    Param(
        [Yaml] $yaml,
        [hashtable] $repoSettings
    )

    if($repoSettings.Keys -notcontains 'UpdateALGoSystemFilesEnvironment') {
        # If UpdateALGoSystemFilesEnvironment is not set, we don't need to do anything
        return
    }

    $updateALGoSystemFilesEnvironment = $repoSettings.UpdateALGoSystemFilesEnvironment
    Write-Host "Setting 'Update AL-Go System Files' environment to $updateALGoSystemFilesEnvironment"

    # Add or replace the environment: section in the UpdateALGoSystemFiles job
    $updateALGoSystemFilesJob = $yaml.Get('jobs:/UpdateALGoSystemFiles:/')

    if(-not $updateALGoSystemFilesJob) {
        # Defensively check that the UpdateALGoSystemFiles job exists
        throw "No UpdateALGoSystemFiles job found in the workflow"
    }

    $environmentSection = $updateALGoSystemFilesJob.Get('environment:')
    if($environmentSection) {
        # If the environment: section already exists, replace it with the new environment
        $updateALGoSystemFilesJob.Replace($environmentSection, "environment: $updateALGoSystemFilesEnvironment")
    }
    else {
        # If the environment: section does not exist, add it
        $updateALGoSystemFilesJob.Insert(1, "environment: $updateALGoSystemFilesEnvironment")
    }

    $yaml.Replace('jobs:/UpdateALGoSystemFiles:/', $updateALGoSystemFilesJob.content)
}

function GetWorkflowContentWithChangesFromSettings {
    Param(
        [string] $srcFile,
        [hashtable] $repoSettings,
        [int] $depth,
        [bool] $includeBuildPP
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($srcFile)
    $yaml = [Yaml]::Load($srcFile)
    $yamlName = $yaml.get('name:')
    if ($yamlName) {
        $workflowName = $yamlName.content.SubString('name:'.Length).Trim().Trim('''"').Trim()
    }
    else {
        $workflowName = $baseName
    }

    $workflowScheduleKey = "WorkflowSchedule"
    $workflowConcurrencyKey = "WorkflowConcurrency"
    foreach($key in @($workflowScheduleKey,$workflowConcurrencyKey)) {
        if ($repoSettings.Keys -contains $key -and ($repoSettings."$key")) {
            throw "The $key setting is not allowed in the global repository settings. Please use the workflow specific settings file or conditional settings."
        }
    }

    # Re-read settings and this time include workflow specific settings
    $repoSettings = ReadSettings -buildMode '' -project '' -workflowName $workflowName -userName '' -branchName '' | ConvertTo-HashTable -recurse

    # Old Schedule key is deprecated, but still supported
    $oldWorkflowScheduleKey = "$($baseName)Schedule"
    if ($repoSettings.Keys -contains $oldWorkflowScheduleKey) {
        # DEPRECATION: REPLACE WITH ERROR AFTER October 1st 2025 --->
        if ($repoSettings.Keys -contains $workflowScheduleKey) {
            OutputWarning "Both $oldWorkflowScheduleKey and $workflowScheduleKey are defined in the settings file. $oldWorkflowScheduleKey will be ignored. This warning will become an error in the future"
        }
        else {
            Trace-DeprecationWarning -Message "$oldWorkflowScheduleKey is deprecated" -DeprecationTag "_workflow_Schedule" -WillBecomeError
            # Convert the old <workflow>Schedule setting to the new WorkflowSchedule setting
            $repoSettings."$workflowScheduleKey" = @{ "cron" = $repoSettings."$oldWorkflowScheduleKey" }
        }
        # <--- REPLACE WITH ERROR AFTER October 1st 2025
    }

    # Any workflow (except for the PullRequestHandler and reusable workflows (_*)) can have concurrency and schedule defined
    if ($baseName -ne "PullRequestHandler" -and $baseName -notlike '_*') {
        # Add Schedule and Concurrency settings to the workflow
        if ($repoSettings.Keys -contains $workflowScheduleKey) {
            if ($repoSettings."$workflowScheduleKey" -isnot [hashtable] -or $repoSettings."$workflowScheduleKey".Keys -notcontains 'cron' -or $repoSettings."$workflowScheduleKey".cron -isnot [string]) {
                throw "The $workflowScheduleKey setting must be a structure containing a cron property"
            }
            # Replace or add the schedule part under the on: key
            $yaml.ReplaceOrAdd('on:/', 'schedule:', @("- cron: '$($repoSettings."$workflowScheduleKey".cron)'"))
        }
        if ($repoSettings.Keys -contains $workflowConcurrencyKey) {
            # Replace or add the concurrency part
            $yaml.ReplaceOrAdd('', 'concurrency:', $repoSettings."$workflowConcurrencyKey")
        }
    }

    if ($baseName -eq "CICD") {
        ModifyCICDWorkflow -yaml $yaml -repoSettings $repoSettings
    }

    if ($baseName -eq "PullRequestHandler") {
        ModifyPullRequestHandlerWorkflow -yaml $yaml -repoSettings $repoSettings
    }

    $criticalWorkflows = @('UpdateGitHubGoSystemFiles', 'Troubleshooting')
    $allowedRunners = @('windows-latest', 'ubuntu-latest')
    $modifyRunsOnAndShell = $true

    # Critical workflows may only run on allowed runners (must always be able to run)
    if($criticalWorkflows -contains $baseName) {
        if($allowedRunners -notcontains $repoSettings."runs-on") {
            $modifyRunsOnAndShell = $false
        }
    }

    if ($modifyRunsOnAndShell) {
        ModifyRunsOnAndShell -yaml $yaml -repoSettings $repoSettings
    }

    # PullRequestHandler, CICD, Current, NextMinor and NextMajor workflows all include a build step.
    # If the dependency depth is higher than 1, we need to add multiple dependent build jobs to the workflow
    if ($baseName -eq 'PullRequestHandler' -or $baseName -eq 'CICD' -or $baseName -eq 'Current' -or $baseName -eq 'NextMinor' -or $baseName -eq 'NextMajor') {
        ModifyBuildWorkflows -yaml $yaml -depth $depth -includeBuildPP $includeBuildPP
    }

    if($baseName -eq 'UpdateGitHubGoSystemFiles') {
        ModifyUpdateALGoSystemFiles -yaml $yaml -repoSettings $repoSettings
    }

    # combine all the yaml file lines into a single string with LF line endings
    $yaml.content -join "`n"
}

# Using direct AL-Go repo, we need to change the owner to the templateOwner, the repo names to AL-Go and AL-Go/Actions and the branch to templateBranch

function ReplaceOwnerRepoAndBranch {
    Param(
        [ref] $srcContent,
        [string] $templateOwner,
        [string] $templateBranch
    )

    $lines = $srcContent.Value.Split("`n")

    # The Original Owner and Repo in the AL-Go repository are microsoft/AL-Go-Actions, microsoft/AL-Go-PTE and microsoft/AL-Go-AppSource
    $originalOwnerAndRepo = @{
        "actionsRepo" = "microsoft/AL-Go-Actions"
        "perTenantExtensionRepo" = "microsoft/AL-Go-PTE"
        "appSourceAppRepo" = "microsoft/AL-Go-AppSource"
    }
    # Original branch is always main
    $originalBranch = "main"

    # Modify the file to use repository names based on whether or not we are using the direct AL-Go repo
    $templateRepos = @{
        "actionsRepo" = "AL-Go/Actions"
        "perTenantExtensionRepo" = "AL-Go"
        "appSourceAppRepo" = "AL-Go"
    }

    # Replace URL's to actions repository first
    $regex = "^(.*)https:\/\/raw\.githubusercontent\.com\/microsoft\/AL-Go-Actions\/$originalBranch(.*)$"
    $replace = "`${1}https://raw.githubusercontent.com/$($templateOwner)/AL-Go/$($templateBranch)/Actions`${2}"
    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }

    # Replace the owner and repo names in the workflow
    "actionsRepo","perTenantExtensionRepo","appSourceAppRepo" | ForEach-Object {
        $regex = "^(.*)$($originalOwnerAndRepo."$_")(.*)$originalBranch(.*)$"
        $replace = "`${1}$($templateOwner)/$($templateRepos."$_")`${2}$($templateBranch)`${3}"
        $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
    }
    $srcContent.Value = $lines -join "`n"
}

function IsDirectALGo {
    param (
        [string] $templateUrl
    )
    $directALGo = $templateUrl -like 'https://github.com/*/AL-Go@*'
    if ($directALGo) {
        if ($templateUrl -like 'https://github.com/microsoft/AL-Go@*' -and -not ($templateUrl -like 'https://github.com/microsoft/AL-Go@*/*')) {
            throw "You cannot use microsoft/AL-Go as a template repository. Please use microsoft/AL-Go-PTE, microsoft/AL-Go-AppSource or a fork of AL-Go instead."
        }
    }
    return $directALGo
}

function GetSrcFolder {
    Param(
        [string] $repoType,
        [string] $templateUrl,
        [string] $templateFolder,
        [string] $srcPath
    )
    Write-Host $templateUrl
    Write-Host $templateFolder
    Write-Host $srcPath
    if (!$templateUrl) {
        return ''
    }
    if (IsDirectALGo -templateUrl $templateUrl) {
        switch ($repoType) {
            "PTE" {
                $typePath = "Per Tenant Extension"
            }
            "AppSource App" {
                $typePath = "AppSource App"
            }
            default {
                throw "Unknown repository type"
            }
        }
        $path = Join-Path $templateFolder "*/Templates/$typePath/.github/workflows"
    }
    else {
        $path = Join-Path $templateFolder "*/.github/workflows"
    }
    # Due to this PowerShell bug: https://github.com/PowerShell/PowerShell/issues/6473#issuecomment-375930843
    # We need to resolve the path of a non-hidden folder (.github/workflows)
    # and then get the parent folder of the parent folder of that path
    $path = Resolve-Path -Path $path -ErrorAction SilentlyContinue
    if (!$path) {
        throw "No workflows found in the template repository"
    }
    $path = Join-Path -Path (Split-Path -Path (Split-Path -Path $path -Parent) -Parent) -ChildPath $srcPath
    return $path
}

function GetModifiedSettingsContent {
    Param(
        [string] $srcSettingsFile,
        [string] $dstSettingsFile
    )

    $srcSettings = Get-ContentLF -Path $srcSettingsFile | ConvertFrom-Json

    $dstSettings = $null
    if(Test-Path -Path $dstSettingsFile -PathType Leaf) {
        $dstSettings = Get-ContentLF -Path $dstSettingsFile | ConvertFrom-Json
    }

    if(!$dstSettings) {
        # If the destination settings file does not exist or it's empty, create an new settings object with default values from the source settings (which includes the $schema property already)
        $dstSettings = $srcSettings
    }
    else {
        # Change the $schema property to be the same as the source settings file (add it if it doesn't exist)
        $schemaKey = '$schema'
        if ($srcSettings.PSObject.Properties.Name -eq $schemaKey) {
            $schemaValue = $srcSettings."$schemaKey"

            $dstSettings | Add-Member -MemberType NoteProperty -Name "$schemaKey" -Value $schemaValue -Force

            # Make sure the $schema property is the first property in the object
            $dstSettings = $dstSettings | Select-Object @{ Name = '$schema'; Expression = { $_.'$schema' } }, * -ExcludeProperty '$schema'
        }
    }

    return $dstSettings | ConvertTo-JsonLF
}

function UpdateSettingsFile {
    Param(
        [string] $settingsFile,
        [hashtable] $updateSettings
    )

    $modified = $false
    # Update Repo Settings file with the template URL
    if (Test-Path $settingsFile) {
        $settings = Get-Content $settingsFile -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        $settings = [PSCustomObject]@{}
        $modified = $true
    }
    foreach($key in $updateSettings.Keys) {
        if ($settings.PSObject.Properties.Name -eq $key) {
            if ($settings."$key" -ne $updateSettings."$key") {
                $settings."$key" = $updateSettings."$key"
                $modified = $true
            }
        }
        else {
            # Add the property if it doesn't exist
            $settings | Add-Member -MemberType NoteProperty -Name "$key" -Value $updateSettings."$key"
            $modified = $true
        }
    }
    if ($modified) {
        # Save the file with LF line endings and UTF8 encoding
        $settings | Set-JsonContentLF -path $settingsFile
    }
    return $modified
}
