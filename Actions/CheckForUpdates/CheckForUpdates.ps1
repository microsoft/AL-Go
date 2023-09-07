Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $templateUrl = "",
    [Parameter(HelpMessage = "Branch in template repository to use for the update (default is the default branch)", Mandatory = $false)]
    [string] $templateBranch = "",
    [Parameter(HelpMessage = "Set this input to Y in order to update AL-Go System Files if needed", Mandatory = $false)]
    [bool] $update,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "yamlclass.ps1")

    DownloadAndImportBcContainerHelper

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0071' -parentTelemetryScopeJson $parentTelemetryScopeJson

    if ($update) {
        if (-not $token) {
            throw "A personal access token with permissions to modify Workflows is needed. You must add a secret called GhTokenWorkflow containing a personal access token. You can Generate a new token from https://github.com/settings/tokens. Make sure that the workflow scope is checked."
        }
        else {
            $token = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($token))
        }
    }

    # Support old calling convention
    if (-not $templateUrl.Contains('@')) {
        if ($templateBranch) {
            $templateUrl += "@$templateBranch"
        }
        else {
            $templateUrl += "@main"
        }
    }
    if ($templateUrl -notlike "https://*") {
        $templateUrl = "https://github.com/$templateUrl"
    }

    # DirectALGo is used to determine if the template is a direct link to an AL-Go repository
    $directALGo = $templateUrl -like 'https://github.com/*/AL-Go@*'
    if ($directALGo) {
        if ($templateUrl -like 'https://github.com/microsoft/AL-Go@*') {
            throw "You cannot use microsoft/AL-Go as a template repository. Please use a fork of AL-Go instead."
        }
    }

    # TemplateUrl is now always a full url + @ and a branch name

    # CheckForUpdates will read all AL-Go System files from the Template repository and compare them to the ones in the current repository
    # CheckForUpdates will apply changes to the AL-Go System files based on AL-Go repo settings, such as "runs-on", "UseProjectDependencies", etc.
    # if $update is set to true, CheckForUpdates will also update the AL-Go System files in the current repository using a PR or a direct commit (if $directCommit is set to true)
    # if $update is set to false, CheckForUpdates will only check for updates and output a warning if there are updates available

    # Get Repo settings as a hashtable
    $repoSettings = ReadSettings -project '' -workflowName '' -userName '' -branchName '' | ConvertTo-HashTable
    $unusedALGoSystemFiles = $repoSettings.unusedALGoSystemFiles

    # if UpdateSettings is true, we need to update the settings file with the new template url (i.e. there are changes to your AL-Go System files)
    $updateSettings = $true
    if ($repoSettings.templateUrl -eq $templateUrl) {
        # No need to update settings file
        $updateSettings = $false
    }

    AddTelemetryProperty -telemetryScope $telemetryScope -key "templateUrl" -value $templateUrl

    $templateBranch = $templateUrl.Split('@')[1]
    $templateUrl = $templateUrl.Split('@')[0]
    $templateOwner = $templateUrl.Split('/')[3]

    # Build the $archiceUrl instead of using the GitHub API
    # The GitHub API has a rate limit of 60 requests per hour, which is not enough for a large number of repositories using AL-Go
    $archiveUrl = "$($templateUrl -replace "https://www.github.com/","$ENV:GITHUB_API_URL/repos/" -replace "https://github.com/","$ENV:GITHUB_API_URL/repos/")/zipball/$templateBranch"

    Write-Host "Using template from $templateUrl@$templateBranch"
    Write-Host "Using ArchiveUrl $archiveUrl"

    # Download the template repository and unpack to a temp folder
    $headers = @{
        "Accept" = "application/vnd.github.baptiste-preview+json"
        "token" = $token
    }
    $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    InvokeWebRequest -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip" -retry
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"

    # CheckFiles is an array of hashtables with the following properties:
    # dstPath: The path to the file in the current repository
    # srcPath: The path to the file in the template repository
    # pattern: The pattern to use when searching for files in the template repository
    # type: The type of file (script, workflow, releasenotes)
    # The files currently checked are:
    # - All files in .github/workflows
    # - All files in .github that ends with .copy.md
    # - All PowerShell scripts in .AL-Go folders (all projects)
    $srcGitHubPath = '.github'
    $srcALGoPath = '.AL-Go'
    if ($directALGo) {
        # When using a direct link to an AL-Go repository, the files are in a subfolder of the template repository
        $typePath = $repoSettings.type
        if ($typePath -eq "PTE") {
            $typePath = "Per Tenant Extension"
        }
        $srcGitHubPath = Join-Path "Templates/$typePath" $srcGitHubPath
        $srcALGoPath = Join-Path "Templates/$typePath" $srcALGoPath
    }
    $checkfiles = @(
        @{ "dstPath" = Join-Path ".github" "workflows"; "srcPath" = Join-Path $srcGitHubPath 'workflows'; "pattern" = "*"; "type" = "workflow" },
        @{ "dstPath" = ".github"; "srcPath" = $srcGitHubPath; "pattern" = "*.copy.md"; "type" = "releasenotes" }
    )
    # Get the list of projects in the current repository
    $baseFolder = $ENV:GITHUB_WORKSPACE
    if ($repoSettings.projects) {
        $projects = $repoSettings.projects
    }
    else {
        $projects = @(Get-ChildItem -Path $baseFolder -Recurse -Depth 2 -Force | Where-Object { $_.PSIsContainer -and (Test-Path (Join-Path $_.FullName ".AL-Go/settings.json") -PathType Leaf) } | ForEach-Object { $_.FullName.Substring($baseFolder.length+1) })
    }
    # To support single project repositories, we check for the .AL-Go folder in the root
    if (Test-Path (Join-Path $baseFolder ".AL-Go")) {
        $projects += @(".")
    }
    $projects | ForEach-Object {
        $checkfiles += @(@{ "dstPath" = Join-Path $_ ".AL-Go"; "srcPath" = $srcALGoPath; "pattern" = "*.ps1"; "type" = "script" })
    }

    # $updateFiles will hold an array of files, which needs to be updated
    $updateFiles = @()
    # $removeFiles will hold an array of files, which needs to be removed
    $removeFiles = @()

    Write-Host "Projects found: $($projects.Count)"
    $projects | ForEach-Object {
        Write-Host "- $_"
    }

    # If useProjectDependencies is true, we need to calculate the dependency depth for all projects
    # Dependency depth determines how many build jobs we need to run sequentially
    # Every build job might spin up multiple jobs in parallel to build the projects without unresolved deependencies
    $depth = 1
    if ($repoSettings.useProjectDependencies -and $projects.Count -gt 1) {
        $buildAlso = @{}
        $projectDependencies = @{}
        $projectsOrder = AnalyzeProjectDependencies -baseFolder $baseFolder -projects $projects -buildAlso ([ref]$buildAlso) -projectDependencies ([ref]$projectDependencies)

        $depth = $projectsOrder.Count
        Write-Host "Calculated dependency depth to be $depth"
    }

    # Loop through all folders in CheckFiles and check if there are any files that needs to be updated
    $checkfiles | ForEach-Object {
        Write-Host "Checking $($_.srcPath)\$($_.pattern)"
        $type = $_.type
        $srcPath = $_.srcPath
        $dstPath = $_.dstPath
        $dstFolder = Join-Path $baseFolder $dstPath
        $srcFolder = Resolve-Path -path (Join-Path $tempName "*\$($srcPath)") -ErrorAction SilentlyContinue
        if ($srcFolder) {
            # Loop through all files in the template repository matching the pattern
            Get-ChildItem -Path $srcFolder -Filter $_.pattern | ForEach-Object {
                # Read the template file and modify it based on the settings
                # Compare the modified file with the file in the current repository
                $srcFile = $_.FullName
                $fileName = $_.Name
                Write-Host "- $filename"
                $baseName = $_.BaseName
                $name = $type
                if ($type -eq "workflow") {
                    # for workflow files, we might need to modify the file based on the settings
                    $yaml = [Yaml]::Load($srcFile)
                    $name = "$type $($yaml.get('name:').content[0].SubString(5).trim())"
                    $workflowScheduleKey = "$($baseName)Schedule"

                    # Any workflow (except for the PullRequestHandler) can have a RepoSetting called <workflowname>Schedule, which will be used to set the schedule for the workflow
                    if ($baseName -ne "PullRequestHandler") {
                        if ($repoSettings.Keys -contains $workflowScheduleKey) {
                            # Read the section under the on: key and add the schedule section
                            $yamlOn = $yaml.Get('on:/')
                            $yaml.Replace('on:/', $yamlOn.content+@('schedule:', "  - cron: '$($repoSettings."$workflowScheduleKey")'"))
                        }
                    }

                    # The CICD workflow can have a RepoSetting called CICDPushBranches, which will be used to set the branches for the workflow
                    # Setting the CICDSchedule will disable the push trigger for the CI/CD workflow (unless CICDPushBranches is set)
                    if ($baseName -eq "CICD") {
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
                            $yaml.Replace('on:/push:/branches:', "branches: [ '$($cicdPushBranches -join "', '")' ]")
                        }
                        else {
                            $yaml.Replace('on:/push:',@())
                        }
                    }

                    if ($baseName -eq "PullRequestHandler") {
                        # The PullRequestHandler workflow can have a RepoSetting called PullRequestTrigger which specifies the trigger to use for Pull Requests
                        $triggerSection = $yaml.Get('on:/pull')
                        $triggerSection.content = "$($repoSettings.PullRequestTrigger):"
                        $yaml.Replace('on:/pull', $triggerSection.Content)

                        # The PullRequestHandler workflow can have a RepoSetting called CICDPullRequestBranches, which will be used to set the branches for the workflow
                        if ($repoSettings.Keys -contains 'CICDPullRequestBranches') {
                            $CICDPullRequestBranches = $repoSettings.CICDPullRequestBranches
                        }
                        else {
                            $CICDPullRequestBranches = $defaultCICDPullRequestBranches
                        }

                        # update the branches: line with the new branches
                        $yaml.Replace("on:/$($repoSettings.PullRequestTrigger):/branches:", "branches: [ '$($CICDPullRequestBranches -join "', '")' ]")
                    }

                    # Repo Setting runs-on and shell determines which GitHub runner is used for all non-build jobs (build jobs are run using the GitHubRunner/GitHubRunnerShell repo settings)
                    # The default for runs-on is windows-latest and the default for shell is powershell
                    # The default for GitHubRunner/GitHubRunnerShell is runs-on/shell (unless Ubuntu-latest are selected here, as build jobs cannot run on Ubuntu)
                    # We do not change runs-on in Update AL Go System Files and Pull Request Handler workflows
                    # These workflows will always run on windows-latest (or maybe Ubuntu-latest later) and not follow settings
                    # Reasons:
                    # - Update AL-Go System files is needed for changing runs-on - by having non-functioning runners, you might dead-lock yourself
                    # - Pull Request Handler workflow for security reasons
                    if ($baseName -ne "UpdateGitHubGoSystemFiles" -and $baseName -ne "PullRequestHandler") {
                        if ($repoSettings."runs-on" -ne "windows-latest") {
                            Write-Host "Setting runs-on to [ $($repoSettings."runs-on") ]"
                            $yaml.ReplaceAll('runs-on: [ windows-latest ]', "runs-on: [ $($repoSettings."runs-on") ]")
                        }
                        if ($repoSettings.shell -ne "powershell") {
                            Write-Host "Setting shell to $($repoSettings.shell)"
                            $yaml.ReplaceAll('shell: powershell', "shell: $($repoSettings.shell)")
                        }
                    }

                    # PullRequestHandler, CICD, Current, NextMinor and NextMajor workflows all include a build step.
                    # If the dependency depth is higher than 1, we need to add multiple dependent build jobs to the workflow
                    if ($baseName -eq 'PullRequestHandler' -or $baseName -eq 'CICD' -or $baseName -eq 'Current' -or $baseName -eq 'NextMinor' -or $baseName -eq 'NextMajor') {
                        $yaml.Replace('env:/workflowDepth:',"workflowDepth: $depth")

                        if ($depth -gt 1) {
                            # Also, duplicate the build job for each dependency depth

                            $build = $yaml.Get('jobs:/Build:/')
                            if($build)
                            {
                                $newBuild = @()

                                1..$depth | ForEach-Object {
                                    $index = $_-1

                                    # All build job needs to have a dependency on the Initialization job
                                    $needs = @('Initialization')
                                    if ($_ -eq 1) {
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
                                        ($_-1)..1 | ForEach-Object {
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
                                    if ($depth -eq $_) {
                                        $newBuild += @("Build:")
                                    }
                                    else {
                                        $newBuild += @("Build$($_):")
                                    }
                                    # Add the content of the calculated build job to the new build job list with an indentation of 2 spaces
                                    $build.content | ForEach-Object { $newBuild += @("  $_") }
                                }

                                # Replace the entire build: job with the new build job list
                                $yaml.Replace('jobs:/Build:', $newBuild)
                            }
                        }
                    }
                    # combine all the yaml file lines into a single string with LF line endings
                    $srcContent = $yaml.content -join "`n"
                }
                else {
                    # For non-workflow files, just read the file content
                    $srcContent = Get-ContentLF -Path $srcFile
                }

                $srcContent = $srcContent.Replace('{TEMPLATEURL}', "$($templateUrl)@$($templateBranch)")
                if ($directALGo) {
                    # If we are using the direct AL-Go repo, we need to change the owner and repo names in the workflow
                    $lines = $srcContent.Split("`n")

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
                    $srcContent = $lines -join "`n"
                }

                $dstFile = Join-Path $dstFolder $fileName
                $dstFileExists = Test-Path -Path $dstFile -PathType Leaf
                if ($unusedALGoSystemFiles -contains $fileName) {
                    # file is not used by ALGo, remove it if it exists
                    # do not add it to $updateFiles if it does not exist
                    if ($dstFileExists) {
                        $removeFiles += @(Join-Path $dstPath $filename)
                    }
                }
                elseif ($dstFileExists) {
                    # file exists, compare and add to $updateFiles if different
                    $dstContent = Get-ContentLF -Path $dstFile
                    if ($dstContent -cne $srcContent) {
                        Write-Host "Updated $name ($(Join-Path $dstPath $filename)) available"
                        $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                    }
                }
                else {
                    # new file, add to $updateFiles
                    Write-Host "New $name ($(Join-Path $dstPath $filename)) available"
                    $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                }
            }
        }
    }

    if (-not $update) {
        # $update not set, just issue a warning in the CI/CD workflow that updates are available
        if (($updateFiles) -or ($removeFiles)) {
            OutputWarning -message "There are updates for your AL-Go system, run 'Update AL-Go System Files' workflow to download the latest version of AL-Go."
            AddTelemetryProperty -telemetryScope $telemetryScope -key "updatesExists" -value $true
        }
        else {
            Write-Host "No updates available for AL-Go for GitHub."
            AddTelemetryProperty -telemetryScope $telemetryScope -key "updatesExists" -value $false
        }
    }
    else {
        # $update set, update the files
        if ($updateSettings -or ($updateFiles) -or ($removeFiles)) {
            try {
                # URL for git commands
                $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
                New-Item $tempRepo -ItemType Directory | Out-Null
                Set-Location $tempRepo
                $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
                $url = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

                # Environment variables for hub commands
                $env:GITHUB_USER = $actor
                $env:GITHUB_TOKEN = $token

                # Configure git
                invoke-git config --global user.email "$actor@users.noreply.github.com"
                invoke-git config --global user.name "$actor"
                invoke-git config --global hub.protocol https
                invoke-git config --global core.autocrlf false

                # Clone URL
                invoke-git clone $url

                # Set current location to the repository folder
                Set-Location -Path *

                # checkout branch to update
                invoke-git checkout $updateBranch

                # If $directCommit, then changes are made directly to the default branch
                if (!$directcommit) {
                    # If not direct commit, create a new branch with name, relevant to the current date and base branch, and switch to it
                    $branch = "update-al-go-system-files/$updateBranch/$((Get-Date).ToUniversalTime().ToString(`"yyMMddHHmmss`"))" # e.g. update-al-go-system-files/main/210101120000
                    invoke-git checkout -b $branch
                }

                # Show git status
                invoke-git status

                # Update Repo Settings file with the template URL
                $templateUrl = "$templateUrl@$templateBranch"
                $RepoSettingsFile = Join-Path ".github" "AL-Go-Settings.json"
                if (Test-Path $RepoSettingsFile) {
                    $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json
                }
                else {
                    $repoSettings = [PSCustomObject]@{}
                }
                if ($repoSettings.PSObject.Properties.Name -eq "templateUrl") {
                    $repoSettings.templateUrl = $templateUrl
                }
                else {
                    # Add the property if it doesn't exist
                    $repoSettings | Add-Member -MemberType NoteProperty -Name "templateUrl" -Value $templateUrl
                }
                # Save the file with LF line endings and UTF8 encoding
                $repoSettings | Set-JsonContentLF -path $repoSettingsFile

                # Update the files
                # Calculate the release notes, while updating
                $releaseNotes = ""
                $updateFiles | ForEach-Object {
                    # Create the destination folder if it doesn't exist
                    $path = [System.IO.Path]::GetDirectoryName($_.DstFile)
                    if (-not (Test-Path -path $path -PathType Container)) {
                        New-Item -Path $path -ItemType Directory | Out-Null
                    }
                    if (([System.IO.Path]::GetFileName($_.DstFile) -eq "RELEASENOTES.copy.md") -and (Test-Path $_.DstFile)) {
                        $oldReleaseNotes = Get-ContentLF -Path $_.DstFile
                        while ($oldReleaseNotes) {
                            $releaseNotes = $_.Content
                            if ($releaseNotes.indexOf($oldReleaseNotes) -gt 0) {
                                $releaseNotes = $releaseNotes.SubString(0, $releaseNotes.indexOf($oldReleaseNotes))
                                $oldReleaseNotes = ""
                            }
                            else {
                                $idx = $oldReleaseNotes.IndexOf("`n## ")
                                if ($idx -gt 0) {
                                    $oldReleaseNotes = $oldReleaseNotes.Substring($idx)
                                }
                                else {
                                    $oldReleaseNotes = ""
                                }
                            }
                        }
                    }
                    Write-Host "Update $($_.DstFile)"
                    $_.Content | Set-ContentLF -Path $_.DstFile
                }
                if ($releaseNotes -eq "") {
                    $releaseNotes = "No release notes available!"
                }
                $removeFiles | ForEach-Object {
                    Write-Host "Remove $_"
                    Remove-Item (Join-Path (Get-Location).Path $_) -Force
                }

                # Add changes files to git changeset
                invoke-git add *

                Write-Host "ReleaseNotes:"
                Write-Host $releaseNotes

                $status = invoke-git -returnValue status --porcelain=v1
                if ($status) {
                    $message = "Updated AL-Go System Files"

                    invoke-git commit --allow-empty -m "$message"

                    if ($directcommit) {
                        invoke-git push $url
                    }
                    else {
                        invoke-git push -u $url $branch
                        invoke-gh pr create --fill --head $branch --base $updateBranch --repo $env:GITHUB_REPOSITORY --body "$releaseNotes"
                    }
                }
                else {
                    Write-Host "No changes detected in files"
                }
            }
            catch {
                if ($directCommit) {
                    throw "Failed to update AL-Go System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. (Error was $($_.Exception.Message))"
                }
                else {
                    throw "Failed to create a pull-request to AL-Go System Files. Make sure that the personal access token, defined in the secret called GhTokenWorkflow, is not expired and it has permission to update workflows. (Error was $($_.Exception.Message))"
                }
            }
        }
        else {
            OutputWarning "No updates available for AL-Go for GitHub."
        }
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
