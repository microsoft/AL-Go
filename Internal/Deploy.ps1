[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'directCommit', Justification = 'False positive.')]
Param(
    [Parameter(Mandatory=$true)]
    [Hashtable] $config,
    [Parameter(Mandatory=$true)]
    [string] $token,
    [Parameter(Mandatory=$false)]
    [bool] $directCommit
)

Import-Module (Join-Path $PSScriptRoot "..\Actions\Github-Helper.psm1" -Resolve) -DisableNameChecking

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

function PushChanges
(
    [Parameter(HelpMessage = "The branch Al-Go is being deployed to (e.g. main / v.3.2)", Mandatory = $false)]
    [string] $BaseBranch,
    [Parameter(HelpMessage = "The message on the commit or PR that contains the latest changes", Mandatory = $false)]
    [string] $CommitMessage,
    [Parameter(HelpMessage = "If true, the commit will be pushed directly to the base branch. If false, a pull request will be created", Mandatory = $false)]
    [bool] $DirectCommit
)
{
    invoke-git add .

    if ($DirectCommit) {
        # Direct commit to base branch
        invoke-git commit --allow-empty -m $CommitMessage
        invoke-git push origin $BaseBranch
    } else {
        # Create PR to base branch
        if (-not (git ls-remote --heads origin $BaseBranch)) {
            Write-Host "Branch $BaseBranch does not exist in origin. Creating it"
            invoke-git branch $BaseBranch origin/main
            invoke-git push origin $BaseBranch
        }
        $branchName = "deploy/$BaseBranch/$((Get-Date).ToUniversalTime().ToString(`"yyMMddHHmmss`"))"


        invoke-git checkout -b $branchName origin/$BaseBranch
        invoke-git commit --allow-empty -m $CommitMessage
        invoke-git push origin $branchName
        invoke-gh pr create --base $BaseBranch --title $CommitMessage --body $CommitMessage
    }
}

$oldPath = Get-Location
try {

    # Authenticate to GIT and GH
    invoke-git config --global user.email "$($config.githubOwner)@users.noreply.github.com"
    invoke-git config --global user.name "$($config.githubOwner)"
    invoke-git config --global hub.protocol https
    invoke-git config --global core.autocrlf false
    $ENV:GITHUB_TOKEN = ''

    Write-Host "Authenticating with GitHub using token"
    $token | invoke-gh auth login --with-token
    $ENV:GITHUB_TOKEN = $token

    # All references inside microsoft/AL-Go and forks of it are to microsoft/AL-Go-Actions@main, microsoft/AL-Go-PTE@main and microsoft/AL-Go-AppSource@main
    # When deploying to new repos, the originalOwnerAndRepo should be changed to the new owner and repo
    $originalOwnerAndRepo = @{
        "actionsRepo"            = "microsoft/AL-Go-Actions"
        "perTenantExtensionRepo" = "microsoft/AL-Go-PTE"
        "appSourceAppRepo"       = "microsoft/AL-Go-AppSource"
    }
    $originalBranch = "main"

    $baseRepoPath = $ENV:GITHUB_WORKSPACE
    Write-Host "Base repo path: $baseRepoPath"
    Set-Location $baseRepoPath

    # Whoami
    $user = invoke-gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" user -silent -returnValue | ConvertFrom-Json
    Write-Host "GitHub user: $($user.login)"

    # Dump configuration
    Write-Host "Configuration:"
    $config | ConvertTo-Json | Out-Host

    # Get Source Branch
    $algoBranch = invoke-git -returnValue branch --show-current
    Write-Host "Source branch: $algoBranch"

    # Calculate Source SHA + Source Owner+Repo
    $srcSHA = invoke-git -returnValue rev-parse HEAD
    $srcUrl = invoke-git -returnValue config --get remote.origin.url
    if ($srcUrl.EndsWith('.git')) { $srcUrl = $srcUrl.Substring(0, $srcUrl.Length - 4) }
    $uri = [Uri]::new($srcUrl)
    $srcOwnerAndRepo = $uri.LocalPath.Trim('/')
    Write-Host "Source SHA: $srcSHA"
    Write-Host "Source Owner+Repo: $srcOwnerAndRepo"

    # baseFolder is the location in which we are going to clone AL-Go-Actions, AL-Go-PTE and AL-Go-AppSource
    $baseFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
    New-Item $baseFolder -ItemType Directory | Out-Null

    # CopyToMain is set when we release to f.ex. v3.2, where we create a new branch on AL-Go-PTE called v3.2, but also copies the changes to the main and the preview branch
    # This way, preview and main will always be up to date with the latest release
    $copyToMain = $config.ContainsKey('copyToMain') -and $config.copyToMain
    if ($copyToMain -and ($config.branch -eq 'preview' -or $config.branch -eq 'main' -or $algoBranch -ne 'main')) {
        throw "You cannot use copyToMain when deploying to the preview or main branch. You also cannot use copyToMain when deploying from other branches than main. copyToMain is only for release branches"
    }

    $appSourceAppRepoPath = Join-Path $baseFolder $config.appSourceAppRepo
    $perTenantExtensionRepoPath = Join-Path $baseFolder $config.perTenantExtensionRepo
    $repos = @(
        @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = $config.branch }
        @{ "repo" = $config.appSourceAppRepo; "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App"; "dstPath" = $appSourceAppRepoPath; "branch" = $config.branch }
    )

    $dstOwnerAndRepo = @{
        "perTenantExtensionRepo" = "$($config.githubOwner)/$($config.perTenantExtensionRepo)"
        "appSourceAppRepo" = "$($config.githubOwner)/$($config.appSourceAppRepo)"
    }

    if ($config.branch -eq 'preview' -or $config.githubOwner -ne 'microsoft') {
        # When deploying to preview, we are NOT going to deploy to a branch in the AL-Go-Actions repository
        # Instead, we are going to have AL-Go-PTE and AL-Go-AppSource point directly to the SHA in AL-Go
        $dstOwnerAndRepo += @{
            "actionsRepo" = "$srcOwnerAndRepo/Actions@$srcSHA"
        }
    }
    else {
        # When deploying to a release branch, we are going to deploy to a branch in the AL-Go-Actions repository
        $actionsRepoPath = Join-Path $baseFolder $config.actionsRepo
        $repos += @(
            @{ "repo" = $config.actionsRepo; "srcPath" = Join-Path $baseRepoPath "Actions"; "dstPath" = $actionsRepoPath; "branch" = $config.branch }
        )
        $dstOwnerAndRepo += @{
            "actionsRepo" = "$($config.githubOwner)/$($config.actionsRepo)@$($config.branch)"
        }
    }

    $additionalRepos = @()
    if ($copyToMain) {
        # copyToMain can only be set to true for release branches (not preview or main)
        Write-Host "Copy template repositories to main branch"
        $additionalRepos = @(
            @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = "main" }
            @{ "repo" = $config.appSourceAppRepo;       "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App";        "dstPath" = $appSourceAppRepoPath;       "branch" = "main" }
            @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                        "dstPath" = $actionsRepoPath;            "branch" = "main" }
            @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = "preview" }
            @{ "repo" = $config.appSourceAppRepo;       "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App";        "dstPath" = $appSourceAppRepoPath;       "branch" = "preview" }
        )
    }

    Write-Host 'Deploying to the following repos:'
    $additionalRepos + $repos | ForEach-Object {
        Write-Host "- from $($srcOwnerAndRepo)/$($_.srcPath)@$($algoBranch) to $($config.githubOwner)/$($_.repo)@$($_.branch)"
    }

    $additionalRepos + $repos | ForEach-Object {
        Set-Location $baseFolder
        $repo = $_.repo
        $srcPath = $_.srcPath
        $dstPath = $_.dstPath
        $branch = $_.branch

        Write-Host -ForegroundColor Yellow "Deploying to $repo"

        try {
            $serverUrl = "https://$($user.login):$token@github.com/$($config.githubOwner)/$repo.git"
            if (Test-Path $repo) {
                Remove-Item $repo -Recurse -Force
            }
            invoke-git clone --quiet $serverUrl
            Set-Location $repo
            try {
                invoke-git checkout $branch
                Get-ChildItem -Path "." -Exclude ".git" -Force | Remove-Item -Force -Recurse
            }
            catch {
                invoke-git checkout -b $branch
                invoke-git commit --allow-empty -m 'init'
                invoke-git branch -M $branch
                invoke-git remote set-url origin $serverUrl
                invoke-git push -u origin $branch
            }
        }
        catch {
            Write-Host "gh repo create $($config.githubOwner)/$repo --public --clone"
            $ownerRepo = "$($config.githubOwner)/$repo"
            invoke-gh repo create $ownerRepo --public --clone
            Start-Sleep -Seconds 10
            Set-Location $repo
            invoke-git checkout -b $branch
            invoke-git commit --allow-empty -m 'init'
            invoke-git branch -M $branch
            invoke-git remote set-url origin $serverUrl
            invoke-git push -u origin $branch
        }

        Get-ChildItem -Path $srcPath -Recurse -File -Force | ForEach-Object {
            $srcFile = $_.FullName
            $dstFile = $dstPath + $srcFile.Substring($srcPath.Length)
            $dstFilePath = [System.IO.Path]::GetDirectoryName($dstFile)

            if (!(Test-Path $dstFilePath -PathType Container)) {
                New-Item $dstFilePath -ItemType Directory | Out-Null
            }
            $lines = ([string](Get-ContentLF -path $srcFile)).Split("`n")
            "actionsRepo", "perTenantExtensionRepo", "appSourceAppRepo" | ForEach-Object {
                if ($_ -eq "actionsRepo") {
                    $useRepo = $dstOwnerAndRepo."$_".Split('@')[0]
                    $useBranch = $dstOwnerAndRepo."$_".Split('@')[1]
                }
                else {
                    $useRepo = $dstOwnerAndRepo."$_"
                    $useBranch = $branch
                }

                # Replace URL's to actions repository first if we are deploying to a preview branch
                # When deploying to a release branch, these URLs are replaced by the following code
                if ($config.branch -eq 'preview') {
                    $regex = "^(.*)https:\/\/raw\.githubusercontent\.com\/microsoft\/AL-Go-Actions\/$originalBranch(.*)$"
                    $replace = "`${1}https://raw.githubusercontent.com/$srcOwnerAndRepo/$($srcSHA)/Actions`${2}"
                    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
                }

                # Replace the owner and repo names in the workflow
                $regex = "^(.*)$($originalOwnerAndRepo."$_")(.*)$originalBranch(.*)$"
                $replace = "`${1}$useRepo`${2}$($useBranch)`${3}"
                $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
            }
            if ($_.Name -eq "AL-Go-Helper.ps1" -and ($config.ContainsKey("defaultBcContainerHelperVersion") -and $config.defaultBcContainerHelperVersion)) {
                # replace defaultBcContainerHelperVersion
                $found = $false
                for($idx=0; $idx -lt $lines.count; $idx++) {
                    if ($lines[$idx] -match '^(\s*)\$defaultBcContainerHelperVersion(\s*)=(\s*)"(.*)" # (.*)$') {
                        $lines[$idx] = "$($Matches[1])`$defaultBcContainerHelperVersion$($Matches[2])=$($Matches[3])""$($config.defaultBcContainerHelperVersion)"" # $($Matches[5])"
                        $found = $true
                        break
                    }
                }
                if (-not $found) {
                    throw 'Could not find defaultBcContainerHelperVersion line in AL-Go-Helpers.ps1 matching "^(\s*)\$defaultBcContainerHelperVersion(\s*)=(\s*)"(.*)" # (.*)$"'
                }
            }
            [System.IO.File]::WriteAllText($dstFile, "$($lines -join "`n")`n")
        }
        if (Test-Path -Path (Join-Path '.' '.github') -PathType Container) {
            $releaseNotesFile = Join-Path $baseRepoPath "RELEASENOTES.md"
            $releaseNotes = (Get-Content -Encoding utf8 -Path $releaseNotesFile) -join "`n"
            if ($config.branch -eq 'preview') {
                $releaseNotes = "## $($config.branch)`n`nNote that when using the preview version of AL-Go for GitHub, we recommend you Update your AL-Go system files, as soon as possible when informed that an update is available.`n`n$releaseNotes"
            }
            else {
                $releaseNotes = "## $($config.branch)`n`n$releaseNotes"
            }
            Set-Content -Path (Join-Path "./.github" "RELEASENOTES.copy.md") -Value $releaseNotes -Encoding utf8
        }
        PushChanges -BaseBranch $branch -CommitMessage "Deploying AL-Go from $algoBranch ($srcSHA) to $branch" -DirectCommit $directCommit

    }
}
finally {
    set-location $oldPath
}
