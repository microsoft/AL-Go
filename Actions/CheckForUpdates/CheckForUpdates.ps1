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

$anchors = @{
    "_BuildALGoProject.yaml" = @{
        "BuildALGoProject" = @(
            @{ "Step" = 'Read settings'; "Before" = $false }
            @{ "Step" = 'Read secrets'; "Before" = $false }
            @{ "Step" = 'Build'; "Before" = $true }
            @{ "Step" = 'Build'; "Before" = $false }
            @{ "Step" = 'Cleanup'; "Before" = $true }
        )
    }
}

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

$realTemplateFolder = $null
$templateFolder = DownloadTemplateRepository -headers $headers -templateUrl $templateUrl -templateSha ([ref]$templateSha) -downloadLatest $downloadLatest

$templateBranch = $templateUrl.Split('@')[1]
$templateOwner = $templateUrl.Split('/')[3]

if (IsDirectALGo -templateUrl $templateUrl) {
    $ALGoSettingsFile = Join-Path $templateFolder "*/.github/AL-Go-Settings.json"
    if (Test-Path -Path $ALGoSettingsFile -PathType Leaf) {
        $templateRepoSettings = Get-Content $ALGoSettingsFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -Recurse
        if ($templateRepoSettings.Keys -contains "templateUrl" -and $templateRepoSettings.templateUrl -ne $templateUrl) {
            # The template repository is a url to another AL-Go repository (an indirect template repository)
            # TemplateUrl and TemplateSha from .github/AL-Go-Settings.json in the indirect template reposotiry points to the "real" template repository
            # Copy files and folders from the indirect template repository, but grab the unmodified file from the "real" template repository if it exists and apply customizations
            $realTemplateUrl = $templateRepoSettings.templateUrl
            if ($templateRepoSettings.Keys -contains "templateSha") {
                $realTemplateSha = $templateRepoSettings.templateSha
            }
            else {
                $realTemplateSha = ""
            }
            # Download the "real" template repository - use downloadLatest if no TemplateSha is specified in the indirect template repository
            $realTemplateFolder = DownloadTemplateRepository -headers $headers -templateUrl $realTemplateUrl -templateSha ([ref]$realTemplateSha) -downloadLatest ($realTemplateSha -eq '')
            
            # Set TemplateBranch and TemplateOwner
            # Keep TemplateUrl and TemplateSha pointing to the indirect template repository
            $templateBranch = $realTemplateUrl.Split('@')[1]
            $templateOwner = $realTemplateUrl.Split('/')[3]
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
$checkfiles = @(
    @{ 'dstPath' = Join-Path '.github' 'workflows'; 'srcPath' = Join-Path '.github' 'workflows'; 'pattern' = '*'; 'type' = 'workflow' },
    @{ 'dstPath' = '.github'; 'srcPath' = '.AL-Go'; 'pattern' = '*.copy.md'; 'type' = 'releasenotes' }
)

# Get the list of projects in the current repository
$baseFolder = $ENV:GITHUB_WORKSPACE
$projects = @(GetProjectsFromRepository -baseFolder $baseFolder -projectsFromSettings $repoSettings.projects)
Write-Host "Projects found: $($projects.Count)"
foreach($project in $projects) {
    Write-Host "- $project"
    $checkfiles += @(@{ 'dstPath' = Join-Path $project '.AL-Go'; 'srcPath' = '.AL-Go'; 'pattern' = '*.ps1'; 'type' = 'script' })
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
    $srcFolder = GetSrcFolder -templateUrl $templateUrl -templateFolder $templateFolder -srcPath $srcPath
    $realSrcFolder = $null
    if ($realTemplateFolder) {
        $realSrcFolder = GetSrcFolder -templateUrl $realTemplateUrl -templateFolder $realTemplateFolder -srcPath $srcPath
    }
    if ($srcFolder) {
        Push-Location -Path $srcFolder
        try {
            # Loop through all files in the template repository matching the pattern
            Get-ChildItem -Path $srcFolder -Filter $checkfile.pattern | ForEach-Object {
                # Read the template file and modify it based on the settings
                # Compare the modified file with the file in the current repository
                $fileName = $_.Name
                Write-Host "- $filename"
                $dstFile = Join-Path $dstFolder $fileName
                $srcFile = $_.FullName
                $realSrcFile = $srcFile
                $isFileDirectALGo = IsDirectALGo -templateUrl $templateUrl
                if ($realSrcFolder) {
                    # if SrcFile is an indirect template repository, we need to find the file in the "real" template repository
                    $fname = Join-Path $realSrcFolder (Resolve-Path $srcFile -Relative)
                    if (Test-Path -Path $fname -PathType Leaf) {
                        $realSrcFile = $fname
                        $isFileDirectALGo = IsDirectALGo -templateUrl $tealTemplateUrl
                    }
                }
                if ($type -eq "workflow") {
                    # for workflow files, we might need to modify the file based on the settings
                    $srcContent = GetWorkflowContentWithChangesFromSettings -srcFile $realSrcFile -repoSettings $repoSettings -depth $depth
                }
                else {
                    # For non-workflow files, just read the file content
                    $srcContent = Get-ContentLF -Path $srcFile
                }

                # Replace static placeholders
                $srcContent = $srcContent.Replace('{TEMPLATEURL}', $templateUrl)

                if ($isFileDirectALGo) {
                    # If we are using direct AL-Go repo, we need to change the owner to the remplateOwner, the repo names to AL-Go and AL-Go/Actions and the branch to templateBranch
                    ReplaceOwnerRepoAndBranch -srcContent ([ref]$srcContent) -templateOwner $templateOwner -templateBranch $templateBranch
                }

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
                        if ($realSrcFile -ne $srcFile) {
                            # Apply customizations from indirect template repository
                            $yaml.ApplyCustomizationsFrom($srcFile, $anchors)
                        }
                        $yaml.ApplyCustomizationsFrom($dstFile, $anchors)
                        $srcContent = $yaml.content -join "`n"
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
        finally {
            Pop-Location
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
            # If $directCommit, then changes are made directly to the default branch
            $serverUrl, $branch = CloneIntoNewFolder -actor $actor -token $token -updateBranch $updateBranch -DirectCommit $directCommit -newBranchPrefix 'update-al-go-system-files'

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

            Write-Host "ReleaseNotes:"
            Write-Host $releaseNotes

            CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Update AL-Go System Files" -branch $branch
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
