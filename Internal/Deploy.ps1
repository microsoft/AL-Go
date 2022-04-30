Param(
    [string] $configName = "",
    [switch] $collect,
    [string] $githubOwner,
    [string] $token,
    [string] $algoBranch,
    [switch] $github,
    [switch] $directCommit
)

function invoke-git {
    Param(
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    Write-Host -ForegroundColor Yellow "git $command $remaining"
    $path = [System.IO.Path]::GetTempFileName()
    try {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Invoke-Expression "git $command $remaining 2> $path"
        $ErrorActionPreference = $prev
        if ($lastexitcode -ne 0) { 
            Write-Host -ForegroundColor Red "Error"
            Write-Error (Get-Content $path -raw)
        }
        else {
            Write-Host -ForegroundColor Green (Get-Content $path | Select-Object -First 1)
        }
    }
    finally {
        if (Test-Path $path) {
            Remove-Item $path
        }
    }
}

function invoke-gh {
    Param(
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    Write-Host -ForegroundColor Yellow "gh $command $remaining"
    $ErrorActionPreference = "SilentlyContinue"
    gh $command $remaining
    $ErrorActionPreference = "Stop"
    if ($lastexitcode) { throw "gh $command error" }
}

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$oldPath = Get-Location
try {

    if ($github) {
        if (!$githubOwner -or !$token) { throw "When running deploy in a workflow, you need to set githubOwner and token" }

        invoke-git config --global user.email "$githubOwner@users.noreply.github.com"
        invoke-git config --global user.name "$githubOwner"
        invoke-git config --global hub.protocol https
        invoke-git config --global core.autocrlf true

        $ENV:GITHUB_TOKEN = $token
        gh auth login --with-token
    }

    $originalOwnerAndRepo = @{
        "actionsRepo" = "microsoft/AL-Go-Actions"
        "perTenantExtensionRepo" = "microsoft/AL-Go-PTE"
        "appSourceAppRepo" = "microsoft/AL-Go-AppSource"
    }
    $originalBranch = "main"

    Set-Location $PSScriptRoot
    $baseRepoPath = invoke-git rev-parse --show-toplevel
    Write-Host "Base repo path: $baseRepoPath"
    $user = gh api user | ConvertFrom-Json
    Write-Host "GitHub user: $($user.login)"

    if ($configName -eq "") { $configName = $user.login }
    if ([System.IO.Path]::GetExtension($configName) -eq "") { $configName += ".json" }
    $config = Get-Content $configName | ConvertFrom-Json

    Write-Host "Using config file: $configName"
    $config | ConvertTo-Json | Out-Host

    Set-Location $baseRepoPath

    if ($algoBranch) {
        invoke-git checkout $algoBranch
    }
    else {
        $algoBranch = invoke-git branch --show-current
        Write-Host "Source branch: $algoBranch"
    }
    if ($collect) {
        $status = invoke-git status --porcelain=v1 | Where-Object { $_.SubString(3) -notlike "Internal/*" }
        if ($status) {
            throw "Destination repo is not clean, cannot collect changes into dirty repo"
        }
    }

    $srcUrl = invoke-git config --get remote.origin.url
    if ($srcUrl.EndsWith('.git')) { $srcUrl = $srcUrl.Substring(0,$srcUrl.Length-4) }
    $uri = [Uri]::new($srcUrl)
    $srcOwnerAndRepo = $uri.LocalPath.Trim('/')
    Write-Host "Source Owner+Repo: $srcOwnerAndRepo"

    if (($config.PSObject.Properties.Name -eq "baseFolder") -and ($config.baseFolder)) {
        $baseFolder =  Join-Path $config.baseFolder $config.localFolder 
    }else {
        $baseFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) $config.localFolder
    }

    $copyToMain = $false
    if ($config.PSObject.Properties.Name -eq "copyToMain") {
        $copyToMain = $config.copyToMain
    }

    if (!(Test-Path $baseFolder)) {
        New-Item $baseFolder -ItemType Directory | Out-Null
    }
    Set-Location $baseFolder

    $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
        if (Test-Path $_) {
            Set-Location $_
            if ($collect) {
                $expectedUrl = "https://github.com/$($config.githubOwner)/$_.git"
                $actualUrl = invoke-git config --get remote.origin.url
                if ($expectedUrl -ne $actualUrl) {
                    throw "unexpected git repo - was $actualUrl, expected $expectedUrl"
                }
            }
            else {
                if (Test-Path ".git") {
                    $status = invoke-git status --porcelain
                    if ($status) {
                        throw "Git repo $_ is not clean, please resolve manually"
                    }
                }
            }
            Set-Location $baseFolder
        }
    }

    $actionsRepoPath = Join-Path $baseFolder $config.actionsRepo
    $appSourceAppRepoPath = Join-Path $baseFolder $config.appSourceAppRepo
    $perTenantExtensionRepoPath = Join-Path $baseFolder $config.perTenantExtensionRepo

    if ($collect) {
        Write-Host "This script will collect the changes in $($config.branch) from three repositories:"
        Write-Host
        Write-Host "https://github.com/$($config.githubOwner)/$($config.actionsRepo)  (folder $actionsRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.perTenantExtensionRepo)   (folder $perTenantExtensionRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.appSourceAppRepo)   (folder $appSourceAppRepoPath)"
        Write-Host
        Write-Host "To the $algoBranch branch from $srcOwnerAndRepo (folder $baseRepoPath)"
        Write-Host
    }
    else {
        Write-Host "This script will deploy the $algoBranch branch from $srcOwnerAndRepo (folder $baseRepoPath) to work repos"
        Write-Host
        Write-Host "Destination is the $($config.branch) branch in the followingrepositories:"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.actionsRepo)  (folder $actionsRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.perTenantExtensionRepo)   (folder $perTenantExtensionRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.appSourceAppRepo)  (folder $appSourceAppRepoPath)"
        Write-Host
        Write-Host "Run the collect.ps1 to collect your modifications in these work repos and copy back"
        Write-Host
    }
    if (-not $github) {
        Read-Host "If this is not what you want to do, then press Ctrl+C now, else press Enter."
    }

    $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
        if ($collect) {
            if (Test-Path $_) {
                Set-Location $_
                invoke-git pull
                Set-Location $baseFolder
            }
            else {
                $serverUrl = "https://github.com/$($config.githubOwner)/$_.git"
                invoke-git clone --quiet $serverUrl
            }
        }
        else {
            if (Test-Path $_) {
                Remove-Item $_ -Force -Recurse
            }
        }
    }

    $repos = @(
        @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                        "dstPath" = $actionsRepoPath;            "branch" = $config.branch }
        @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = $config.branch }
        @{ "repo" = $config.appSourceAppRepo;       "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App";        "dstPath" = $appSourceAppRepoPath;       "branch" = $config.branch }
    )

    if ($collect) {
        $baseRepoBranch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
        if ($baseRepoBranch) {
            Set-Location $baseRepoPath
            invoke-git checkout -b $baseRepoBranch
        }

        $repos | ForEach-Object {
            Set-Location $baseFolder
            $repo = $_.repo
            $srcPath = $_.srcPath
            $dstPath = $_.dstPath
        
            Write-Host -ForegroundColor Yellow "Collecting from $repo"

            Get-ChildItem -Path "$srcPath\*" | Where-Object { !($_.PSIsContainer -and $_.Name -eq ".git") } | ForEach-Object {
                if ($_.PSIsContainer) {
                    Remove-Item $_ -Force -Recurse
                }
                else {
                    Remove-Item $_ -Force
                }
            }

            Get-ChildItem "$dstPath\*" -Recurse | Where-Object { !$_.PSIsContainer } | ForEach-Object {
                $dstFile = $_.FullName
                $srcFile = $srcPath + $dstFile.Substring($dstPath.Length)
                $srcFilePath = [System.IO.Path]::GetDirectoryName($srcFile)
                if (!(Test-Path $srcFilePath)) {
                    New-Item $srcFilePath -ItemType Directory | Out-Null
                }
                Write-Host "$dstFile -> $srcFile"
                $lines = ([string](Get-Content -Raw -path $dstFile)).Split("`n")
                "actionsRepo","perTenantExtensionRepo","appSourceAppRepo" | ForEach-Object {
                    $regex = "^(.*)$($config.githubOwner)/$($config."$_")(.*)$($config.branch)(.*)$"
                    $replace = "`$1$($originalOwnerAndRepo."$_")`$2$originalBranch`$3"
                    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
                }
                $lines -join "`n" | Set-Content $srcFile -Force -NoNewline
            }
        }
        Set-Location $baseRepoPath

        if ($github) {
            $serverUrl = "https://$($user.login):$token@github.com/$($srcOwnerAndRepo).git"
        }
        else {
            $serverUrl = "https://github.com/$($srcOwnerAndRepo).git"
        }

        $commitMessage = "Collect changes from $($config.githubOwner)/*@$($config.branch)"
        invoke-git add *
        invoke-git commit --allow-empty -m "'$commitMessage'"
        if ($baseRepoBranch) {
            invoke-git push -u $serverUrl $baseRepoBranch
            invoke-gh pr create --fill --head $baseRepoBranch --repo $srcOwnerAndRepo
            invoke-git checkout $algoBranch
        }
        else {
            invoke-git push $serverUrl
        }
    }
    else {
        $additionalRepos = @()
        if ($copyToMain -and $config.branch -ne "main") {
            Write-Host "Copy template repositories to main branch"
            $additionalRepos = @(
                @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = "main" }
                @{ "repo" = $config.appSourceAppRepo;       "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App";        "dstPath" = $appSourceAppRepoPath;       "branch" = "main" }
                @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                        "dstPath" = $actionsRepoPath;            "branch" = "main" }
                @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = "preview" }
                @{ "repo" = $config.appSourceAppRepo;       "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App";        "dstPath" = $appSourceAppRepoPath;       "branch" = "preview" }
                @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                        "dstPath" = $actionsRepoPath;            "branch" = "preview" }
            )
        }

        $additionalRepos + $repos | ForEach-Object {
            Set-Location $baseFolder
            $repo = $_.repo
            $srcPath = $_.srcPath
            $dstPath = $_.dstPath
            $branch = $_.branch

            Write-Host -ForegroundColor Yellow "Deploying to $repo"

            try {
                if ($github) {
                    $serverUrl = "https://$($user.login):$token@github.com/$($config.githubOwner)/$repo.git"
                }
                else {
                    $serverUrl = "https://github.com/$($config.githubOwner)/$repo.git"
                }
                if (Test-Path $repo) {
                    Remove-Item $repo -Recurse -Force
                }
                invoke-git clone --quiet $serverUrl
                Set-Location $repo
                try {
                    invoke-git checkout $branch
                    Get-ChildItem -Path .\* -Exclude ".git" | Remove-Item -Force -Recurse
                }
                catch {
                    invoke-git checkout -b $branch
                    invoke-git commit --allow-empty -m 'init'
                    invoke-git branch -M $branch
                    if ($github) {
                        invoke-git remote set-url origin $serverUrl
                    }
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
                if ($github) {
                    invoke-git remote set-url origin $serverUrl
                }
                invoke-git push -u origin $branch
            }
        
            Get-ChildItem "$srcPath\*" -Recurse | Where-Object { !$_.PSIsContainer } | ForEach-Object {
                $srcFile = $_.FullName
                $dstFile = $dstPath + $srcFile.Substring($srcPath.Length)
                $dstFilePath = [System.IO.Path]::GetDirectoryName($dstFile)
                if (!(Test-Path $dstFilePath -PathType Container)) {
                    New-Item $dstFilePath -ItemType Directory | Out-Null
                }
                $useBranch = $config.branch
                if ($_.Name -eq "AL-Go-Settings.json") {
                    $useBranch = $branch
                }
                $lines = ([string](Get-Content -Raw -path $srcFile)).Split("`n")
                "actionsRepo","perTenantExtensionRepo","appSourceAppRepo" | ForEach-Object {
                    $regex = "^(.*)$($originalOwnerAndRepo."$_")(.*)$originalBranch(.*)$"
                    $replace = "`$1$($config.githubOwner)/$($config."$_")`$2$($useBranch)`$3"
                    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
                }
                $lines -join "`n" | Set-Content $dstFile -Force -NoNewline
            }
        
            invoke-git add .
            invoke-git commit --allow-empty -m 'checkout'
            invoke-git push $serverUrl
        }
    }
}
finally {
    set-location $oldPath
}
