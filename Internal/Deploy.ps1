Param(
    [string] $configName = "",
    [switch] $collect,
    [string] $actor,
    [string] $token,
    [switch] $confirm
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

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$oldPath = Get-Location
try {
    if ($actor) {
        invoke-git config --global user.email "$actor@users.noreply.github.com"
        invoke-git config --global user.name "$actor"
        invoke-git config --global hub.protocol https
        invoke-git config --global core.autocrlf true
    }

    if ($token) {
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
    $baseRepoPath = git rev-parse --show-toplevel
    Write-Host "Base repo path: $baseRepoPath"
    $user = gh api user | ConvertFrom-Json
    Write-Host "GitHub user: $($user.login)"

    if ($configName -eq "") { $configName = $user.login }
    if ([System.IO.Path]::GetExtension($configName) -eq "") { $configName += ".json" }
    $config = Get-Content $configName | ConvertFrom-Json

    Write-Host "Using config file: $configName"
    $config | ConvertTo-Json | Out-Host

    Set-Location $baseRepoPath

    if ($collect) {
        $status = git status --porcelain=v1 | Where-Object { $_.SubString(3) -notlike "Internal/*" }
        if ($status) {
            throw "Destination repo is not clean, cannot collect changes into dirty repo"
        }
    }
    $srcBranch = git branch --show-current
    Write-Host "Source branch: $srcBranch"

    $srcUrl = git config --get remote.origin.url
    if ($srcUrl.EndsWith('.git')) { $srcUrl = $srcUrl.Substring(0,$srcUrl.Length-4) }
    $uri = [Uri]::new($srcUrl)
    $srcOwnerAndRepo = $uri.LocalPath.Trim('/')
    Write-Host "Source Owner+Repo: $srcOwnerAndRepo"

    if (($config.PSObject.Properties.Name -eq "baseFolder") -and ($config.baseFolder)) {
        $baseFolder =  Join-Path $config.baseFolder $config.localFolder 
    }else {
        $baseFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) $config.localFolder
    }

    if ($collect) {
        if (Test-Path $baseFolder) {
            $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
                Set-Location $baseFolder
                if (Test-Path $_) {
                    Set-Location $_
                    $expectedUrl = "https://github.com/$($config.githubOwner)/$_.git"
                    $actualUrl = git config --get remote.origin.url
                    if ($expectedUrl -ne $actualUrl) {
                        throw "unexpected git repo - was $actualUrl, expected $expectedUrl"
                    }
                }
            }
        }
        else {
            throw "$baseFolder is not found!"
        }
    }
    Set-Location $baseFolder

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
        Write-Host "To the $srcBranch branch from $srcOwnerAndRepo (folder $baseRepoPath)"
        Write-Host
    }
    else {
        Write-Host "This script will deploy the $srcBranch branch from $srcOwnerAndRepo (folder $baseRepoPath) to work repos"
        Write-Host
        Write-Host "Destination is the $($config.branch) branch in the followingrepositories:"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.actionsRepo)  (folder $actionsRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.perTenantExtensionRepo)   (folder $perTenantExtensionRepoPath)"
        Write-Host "https://github.com/$($config.githubOwner)/$($config.appSourceAppRepo)  (folder $appSourceAppRepoPath)"
        Write-Host
        Write-Host "Run the collect.ps1 to collect your modifications in these work repos and copy back"
        Write-Host
    }
    if (-not $confirm) {
        Read-Host "If this is not what you want to do, then press Ctrl+C now, else press Enter."
    }

    if (!$collect) {
        if (Test-Path $baseFolder) {
            $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
                Set-Location $baseFolder
                if (Test-Path $_) {
                    Set-Location $_
                    if (Test-Path ".git") {
                        $status = git status --porcelain
                        if ($status) {
                            throw "Git repo $_ is not clean, please resolve manually"
                        }
                    }
                }
            }
            Set-Location $baseFolder
            $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
                if (Test-Path $_) {
                    Remove-Item $_ -Force -Recurse
                }
            }
        }
        else {
            New-Item $baseFolder -ItemType Directory | Out-Null
        }
    }

    $repos = @(
        @{ "repo" = $config.actionsRepo;            "srcPath" = Join-Path $baseRepoPath "Actions";                        "dstPath" = $actionsRepoPath            }
        @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath }
        @{ "repo" = $config.appSourceAppRepo;       "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App";        "dstPath" = $appSourceAppRepoPath       }
    )

    if ($collect) {
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
    }
    else {
        $repos | ForEach-Object {
            Set-Location $baseFolder
            $repo = $_.repo
            $srcPath = $_.srcPath
            $dstPath = $_.dstPath

            Write-Host -ForegroundColor Yellow "Deploying to $repo"

            try {
                $serverUrl = "https://github.com/$($config.githubOwner)/$repo.git"
                invoke-git clone --quiet $serverUrl
                Set-Location $repo
                try {
                    invoke-git checkout $config.branch
                    Get-ChildItem -Path .\* -Exclude ".git" | Remove-Item -Force -Recurse
                }
                catch {
                    invoke-git checkout -b $config.branch
                    invoke-git commit --allow-empty -m 'init'
                    invoke-git branch -M $config.branch
                    if ($actor -and $token) {
                        invoke-git remote set-url origin "https://$($actor):$token@github.com/$($config.githubOwner)/$repo.git"
                    }
                    invoke-git push -u origin $config.branch
                }
            }
            catch {
                Write-Host "gh repo create $($config.githubOwner)/$repo --public --confirm"
                start-process -FilePath "gh" -ArgumentList @("repo","create","$($config.githubOwner)/$repo","--public","--confirm") -Wait
                Set-Location $repo
                invoke-git checkout -b $config.branch
                invoke-git commit --allow-empty -m 'init'
                invoke-git branch -M $config.branch
                if ($actor -and $token) {
                    invoke-git remote set-url origin "https://$($actor):$token@github.com/$($config.githubOwner)/$repo.git"
                }
                invoke-git push -u origin $config.branch
            }
        
            Get-ChildItem "$srcPath\*" -Recurse | Where-Object { !$_.PSIsContainer } | ForEach-Object {
                $srcFile = $_.FullName
                $dstFile = $dstPath + $srcFile.Substring($srcPath.Length)
                $dstFilePath = [System.IO.Path]::GetDirectoryName($dstFile)
                if (!(Test-Path $dstFilePath -PathType Container)) {
                    New-Item $dstFilePath -ItemType Directory | Out-Null
                }
                $lines = ([string](Get-Content -Raw -path $srcFile)).Split("`n")
                "actionsRepo","perTenantExtensionRepo","appSourceAppRepo" | ForEach-Object {
                    $regex = "^(.*)$($originalOwnerAndRepo."$_")(.*)$originalBranch(.*)$"
                    $replace = "`$1$($config.githubOwner)/$($config."$_")`$2$($config.branch)`$3"
                    $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
                }
                $lines -join "`n" | Set-Content $dstFile -Force -NoNewline
            }
        
            invoke-git add .
            invoke-git commit --allow-empty -m "checkout"
            invoke-git push $serverUrl
        }
    }
}
finally {
    set-location $oldPath
}
