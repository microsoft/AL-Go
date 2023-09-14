Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $templateUrl = "",
    [Parameter(HelpMessage = "Set this input to Y in order to download latest version of the template repository (else it will reuse the SHA from last update)", Mandatory = $false)]
    [bool] $downloadLatest,
    [Parameter(HelpMessage = "Set this input to Y in order to update AL-Go System Files if needed", Mandatory = $false)]
    [bool] $update,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $directCommit
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "yamlclass.ps1")
. (Join-Path -Path $PSScriptRoot -ChildPath "CheckForUpdates.HelperFunctions.ps1")

# ContainerHelper is used for determining project folders and dependencies
DownloadAndImportBcContainerHelper

if ($update) {
    if (-not $token) {
        throw "A personal access token with permissions to modify Workflows is needed. You must add a secret called GhTokenWorkflow containing a personal access token. You can Generate a new token from https://github.com/settings/tokens. Make sure that the workflow scope is checked."
    }
    else {
        $token = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($token))
    }
}

# Use Authenticated API request to avoid the 60 API calls per hour limit
$headers = @{
    "Accept" = "application/vnd.github.baptiste-preview+json"
    "Authorization" = "Bearer $token"
}

if (-not $templateUrl.Contains('@')) {
    $templateUrl += "@main"
}
if ($templateUrl -notlike "https://*") {
    $templateUrl = "https://github.com/$templateUrl"
}
# Remove www part (if exists)
$templateUrl = $templateUrl -replace "^(https:\/\/)(www\.)(.*)$", '$1$3'

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
# if $downloadLatest is set to true, CheckForUpdates will download the latest version of the template repository, else it will use the templateSha setting in the .github/AL-Go-Settings file

# Get Repo settings as a hashtable
$repoSettings = ReadSettings -project '' -workflowName '' -userName '' -branchName '' | ConvertTo-HashTable
$templateSha = $repoSettings.templateSha
$unusedALGoSystemFiles = $repoSettings.unusedALGoSystemFiles

# If templateUrl has changed, download latest version of the template repository (ignore templateSha)
if ($repoSettings.templateUrl -ne $templateUrl -or $templateSha -eq '') {
    $downloadLatest = $true
}

$tempName = DownloadTemplateRepository -headers $headers -templateUrl ([ref]$templateUrl) -templateSha ([ref]$templateSha) -downloadLatest $downloadLatest

$templateBranch = $templateUrl.Split('@')[1]
$templateOwner = $templateUrl.Split('/')[3]

if (!$directALGo) {
    $ALGoSettingsFile = Join-Path $tempName "*/.github/AL-Go-Settings.json"
    if (Test-Path -Path $ALGoSettingsFile -PathType Leaf) {
        $templateRepoSettings = Get-Content $ALGoSettingsFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -Recurse
        if ($templateRepoSettings.Keys -contains "templateUrl" -and $templateRepoSettings.templateUrl -ne $templateUrl) {
            # Template repository has a different template url than the one we are using
            # This means that the template repository is another AL-Go repository and not a template repository
            throw "The template repository has a different template url than the one we are using."
        }
    }
}

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
    $projects = @(GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $repoSettings.projects)
    Write-Host "Projects found: $($projects.Count)"
    foreach($project in $projects) {
        Write-Host "- $project"
        $checkfiles += @(@{ "dstPath" = Join-Path $project ".AL-Go"; "srcPath" = $srcALGoPath; "pattern" = "*.ps1"; "type" = "script" })
    }

    # $updateFiles will hold an array of files, which needs to be updated
    $updateFiles = @()
    # $removeFiles will hold an array of files, which needs to be removed
    $removeFiles = @()

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
    foreach($checkfile in $checkfiles) {
        Write-Host "Checking $($checkfile.srcPath)\$($checkfile.pattern)"
        $type = $checkfile.type
        $srcPath = $checkfile.srcPath
        $dstPath = $checkfile.dstPath
        $dstFolder = Join-Path $baseFolder $dstPath
        $srcFolder = Resolve-Path -path (Join-Path $tempName "*\$($srcPath)") -ErrorAction SilentlyContinue
        if ($srcFolder) {
            # Loop through all files in the template repository matching the pattern
            Get-ChildItem -Path $srcFolder -Filter $checkfile.pattern | ForEach-Object {
                # Read the template file and modify it based on the settings
                # Compare the modified file with the file in the current repository
                $srcFile = $_.FullName
                $fileName = $_.Name
                Write-Host "- $filename"
                if ($type -eq "workflow") {
                    # for workflow files, we might need to modify the file based on the settings
                    $srcContent = GetWorkflowContentWithChangesFromSettings -srcFile $srcFile -repoSettings $repoSettings -depth $depth
                }
                else {
                    # For non-workflow files, just read the file content
                    $srcContent = Get-ContentLF -Path $srcFile
                }

                # Replace static placeholders
                $srcContent = $srcContent.Replace('{TEMPLATEURL}', $templateUrl)

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
                    if ($type -eq 'workflow') {
                        $yaml = [Yaml]::new($srcContent.Split("`n"))
                        try {
                            $dstYaml = [Yaml]::Load($dstFile)
                        }
                        catch {
                            $dstYaml = $null
                        }
                        if ($dstYaml) {
                            # Destination YAML was readable - grab customizations from placeholders
                            foreach($placeholderName in 'BuildALGoProject:Initialize','BuildALGoProject:PreBuild','BuildALGoProject:PostBuild','BuildALGoProject:Finalize') {
                                $jobName = "$($placeholderName.Split(':')[0]):"
                                $stepName = $placeholderName.Split(':')[1]
                                $startStart = 0
                                $startCount = 0
                                $endStart = 0
                                $endCount = 0
                                if ($yaml.Find("jobs:/$jobName/steps:/- name: $($stepName).Start", [ref] $startStart, [ref] $startCount) -and $yaml.Find("jobs:/$jobName/steps:/- name: $($stepName).End", [ref] $endStart, [ref] $endCount)) {
                                    Write-Host "PlaceHolder for $placeholderName found in source YAML: $startStart $startCount $endStart $endCount"
                                    $dstStartStart = 0
                                    $dstStartCount = 0
                                    $dstEndStart = 0
                                    $dstEndCount = 0
                                    if ($dstYaml.Find("jobs:/$jobName/steps:/- name: $($stepName).Start", [ref] $dstStartStart, [ref] $dstStartCount) -and $dstYaml.Find("jobs:/$jobName/steps:/- name: $($stepName).End", [ref] $dstEndStart, [ref] $dstEndCount)) {
                                        Write-Host "PlaceHolder for $placeholderName found in destination YAML: $dstStartStart $dstStartCount $dstEndStart $dstEndCount"
                                        $yaml.content = $yaml.content[0..($startStart+$startCount-1)]+$dstYaml.content[($dstStartStart+$dstStartCount)..($dstEndStart-1)]+$yaml.content[$endStart..($yaml.content.Count-1)]
                                    }
                                }
                            }
                            # Locate custom jobs in destination YAML
                            $jobs = $yaml.GetNextLevel('jobs:/').Trim(':')
                            $dstJobs = $dstYaml.GetNextLevel('jobs:/')
                            $customJobs = @($dstJobs | Where-Object { $_ -like 'CustomJob*:' } | ForEach-Object { $_.Trim(':') })
                            if ($customJobs) {
                                $nativeJobs = ($dstJobs | Where-Object { $customJobs -notcontains $_.Trim(':') }).Trim(':')
                                Write-Host "Custom Jobs:"
                                foreach($customJob in $customJobs) {
                                    Write-Host "- $customJob"
                                    $jobsWithDependency = $nativeJobs | Where-Object { $dstYaml.GetPropertyArray("jobs:/$($_):/needs:") | Where-Object { $_ -eq $customJob } }
                                    if ($jobsWithDependency) {
                                        Write-Host "  - Jobs with dependency: $($jobsWithDependency -join ', ')"
                                        $jobsWithDependency | ForEach-Object {
                                            if ($jobs -contains $_) {
                                                # Add dependency to job
                                                $yaml.Replace("jobs:/$($_):/needs:","needs: [ $(@($yaml.GetPropertyArray("jobs:/$($_):/needs:"))+@($customJob) -join ', ') ]")
                                            }
                                        }
                                    }
                                    $yaml.content += @('') + @($dstYaml.Get("jobs:/$($customJob):").content | ForEach-Object { "  $_" })
                                }
                            }
                            $srcContent = $yaml.content -join "`n"
                        }
                    }
                    # file exists, compare and add to $updateFiles if different
                    $dstContent = Get-ContentLF -Path $dstFile
                    if ($dstContent -cne $srcContent) {
                        Write-Host "Updated $type ($(Join-Path $dstPath $filename)) available"
                        $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                    }
                }
                else {
                    # new file, add to $updateFiles
                    Write-Host "New $type ($(Join-Path $dstPath $filename)) available"
                    $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                }
            }
        }
    }

    $updateSettings = ($repoSettings.templateUrl -ne $templateUrl -or $repoSettings.templateSha -ne $templateSha)
    if (-not $update) {
        # $update not set, just issue a warning in the CI/CD workflow that updates are available
        if (($updateFiles) -or ($removeFiles)) {
            OutputWarning -message "There are updates for your AL-Go system, run 'Update AL-Go System Files' workflow to download the latest version of AL-Go."
        }
        else {
            Write-Host "No updates available for AL-Go for GitHub."
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
                if ($repoSettings.PSObject.Properties.Name -eq "templateSha") {
                    $repoSettings.templateSha = $templateSha
                }
                else {
                    # Add the property if it doesn't exist
                    $repoSettings | Add-Member -MemberType NoteProperty -Name "templateSha" -Value $templateSha
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
