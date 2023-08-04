Param(
    [string] $configName = "",
    [string] $githubOwner,
    [string] $token,
    [string] $algoBranch,
    [switch] $github,
    [switch] $directCommit
)

Import-Module (Join-Path $PSScriptRoot "..\Actions\Github-Helper.psm1" -Resolve) -DisableNameChecking

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Write-Host "::WARNING::The collect mechanism is deprecated. Use the new direct AL-Go development mechanism instead."

$oldPath = Get-Location
try {
    if ($github) {
        if (!$githubOwner -or !$token) { throw "When running deploy in a workflow, you need to set githubOwner and token" }

        invoke-git config --global user.email "$githubOwner@users.noreply.github.com"
        invoke-git config --global user.name "$githubOwner"
        invoke-git config --global hub.protocol https
        invoke-git config --global core.autocrlf false
        $ENV:GITHUB_TOKEN = ''
    }

    Write-Host "Authenticating with GitHub using token"
    $token | invoke-gh auth login --with-token
    if ($github) {
        $ENV:GITHUB_TOKEN = $token
    }

    $originalOwnerAndRepo = @{
        "actionsRepo"            = "microsoft/AL-Go-Actions"
        "perTenantExtensionRepo" = "microsoft/AL-Go-PTE"
        "appSourceAppRepo"       = "microsoft/AL-Go-AppSource"
    }
    $originalBranch = "main"

    Set-Location $PSScriptRoot
    $baseRepoPath = invoke-git -returnValue rev-parse --show-toplevel
    Write-Host "Base repo path: $baseRepoPath"
    $user = invoke-gh api user -silent -returnValue | ConvertFrom-Json
    Write-Host "GitHub user: $($user.login)"

    if ($configName -eq "") { $configName = $user.login }
    if ([System.IO.Path]::GetExtension($configName) -eq "") { $configName += ".json" }
    $config = Get-Content $configName -Encoding UTF8 | ConvertFrom-Json

    Write-Host "Using config file: $configName"
    $config | ConvertTo-Json | Out-Host

    Set-Location $baseRepoPath

    if ($algoBranch) {
        invoke-git checkout $algoBranch
    }
    else {
        $algoBranch = invoke-git -returnValue branch --show-current
        Write-Host "Source branch: $algoBranch"
    }
    $status = invoke-git -returnValue status --porcelain=v1 | Where-Object { ($_) -and ($_.SubString(3) -notlike "Internal/*") }
    if ($status) {
        throw "Destination repo is not clean, cannot collect changes into dirty repo"
    }

    $srcUrl = invoke-git -returnValue config --get remote.origin.url
    if ($srcUrl.EndsWith('.git')) { $srcUrl = $srcUrl.Substring(0, $srcUrl.Length - 4) }
    $uri = [Uri]::new($srcUrl)
    $srcOwnerAndRepo = $uri.LocalPath.Trim('/')
    Write-Host "Source Owner+Repo: $srcOwnerAndRepo"

    if (($config.PSObject.Properties.Name -eq "baseFolder") -and ($config.baseFolder)) {
        $baseFolder = Join-Path $config.baseFolder $config.localFolder
    }
    else {
        $baseFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) $config.localFolder
    }

    if (!(Test-Path $baseFolder)) {
        New-Item $baseFolder -ItemType Directory | Out-Null
    }
    Set-Location $baseFolder

    $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
        if (Test-Path $_) {
            Set-Location $_
            $expectedUrl = "https://github.com/$($config.githubOwner)/$_.git"
            $actualUrl = invoke-git -returnValue config --get remote.origin.url
            if ($expectedUrl -ne $actualUrl) {
                throw "unexpected git repo - was $actualUrl, expected $expectedUrl"
            }
            Set-Location $baseFolder
        }
    }

    $actionsRepoPath = Join-Path $baseFolder $config.actionsRepo
    $appSourceAppRepoPath = Join-Path $baseFolder $config.appSourceAppRepo
    $perTenantExtensionRepoPath = Join-Path $baseFolder $config.perTenantExtensionRepo

    Write-Host "This script will collect the changes in $($config.branch) from three repositories:"
    Write-Host "- https://github.com/$($config.githubOwner)/$($config.actionsRepo)  (folder $actionsRepoPath)"
    Write-Host "- https://github.com/$($config.githubOwner)/$($config.perTenantExtensionRepo)   (folder $perTenantExtensionRepoPath)"
    Write-Host "- https://github.com/$($config.githubOwner)/$($config.appSourceAppRepo)   (folder $appSourceAppRepoPath)"
    Write-Host
    Write-Host "To the $algoBranch branch from $srcOwnerAndRepo (folder $baseRepoPath)"
    Write-Host

    if (-not $github) {
        Read-Host "If this is not what you want to do, then press Ctrl+C now, else press Enter."
    }

    $config.actionsRepo, $config.perTenantExtensionRepo, $config.appSourceAppRepo | ForEach-Object {
        if (Test-Path $_) {
            Set-Location $_
            invoke-git pull
        }
        else {
            $serverUrl = "https://github.com/$($config.githubOwner)/$_.git"
            invoke-git clone --quiet $serverUrl
            Set-Location $_
        }
        invoke-git checkout $config.branch
        Set-Location $baseFolder
    }

    $repos = @(
        @{ "repo" = $config.actionsRepo; "srcPath" = Join-Path $baseRepoPath "Actions"; "dstPath" = $actionsRepoPath; "branch" = $config.branch }
        @{ "repo" = $config.perTenantExtensionRepo; "srcPath" = Join-Path $baseRepoPath "Templates\Per Tenant Extension"; "dstPath" = $perTenantExtensionRepoPath; "branch" = $config.branch }
        @{ "repo" = $config.appSourceAppRepo; "srcPath" = Join-Path $baseRepoPath "Templates\AppSource App"; "dstPath" = $appSourceAppRepoPath; "branch" = $config.branch }
    )

    $baseRepoBranch = ''
    if (!$directCommit) {
        $baseRepoBranch = "collect-from-$($config.branch)/$alGoBranch/$((Get-Date).ToUniversalTime().ToString(`"yyMMddHHmmss`"))" # e.g. collect-from-nopr/main/210101120000
        Set-Location $baseRepoPath
        invoke-git checkout -b $baseRepoBranch
    }

    $repos | ForEach-Object {
        Set-Location $baseFolder
        $repo = $_.repo
        $srcPath = $_.srcPath
        $dstPath = $_.dstPath

        Write-Host "Removing $srcPath content"
        Get-ChildItem -Path $srcPath -Force | Where-Object { !($_.PSIsContainer -and $_.Name -eq ".git") } | ForEach-Object {
            $name = $_.FullName
            Write-Host "Remove $name"
            if ($_.PSIsContainer) {
                Remove-Item $name -Force -Recurse
            }
            else {
                Remove-Item $name -Force
            }
        }

        Write-Host -ForegroundColor Yellow "Collecting from $repo"
        Get-ChildItem -Path $dstPath -Recurse -File -Force | Where-Object { $_.name -notlike '*.copy.md' } | ForEach-Object {
            $dstFile = $_.FullName
            $srcFile = $srcPath + $dstFile.Substring($dstPath.Length)
            $srcFilePath = [System.IO.Path]::GetDirectoryName($srcFile)
            if (!(Test-Path $srcFilePath)) {
                New-Item $srcFilePath -ItemType Directory | Out-Null
            }
            Write-Host "$dstFile -> $srcFile"
            $lines = ([string](Get-ContentLF -path $dstFile)).Split("`n")
            "actionsRepo", "perTenantExtensionRepo", "appSourceAppRepo" | ForEach-Object {
                $regex = "^(.*)$($config.githubOwner)\/$($config."$_")(.*)$($config.branch)(.*)$"
                $replace = "`$1$($originalOwnerAndRepo."$_")`$2$originalBranch`$3"
                $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }
            }
            if ($_.Name -eq "AL-Go-Helper.ps1") {
                $lines = $lines | ForEach-Object { $_ -replace '^(\s*)\$defaultBcContainerHelperVersion(\s*)=(\s*)"(.*)"(.*)$', "`$1`$defaultBcContainerHelperVersion`$2=`$3""""`$5" }
            }
            [System.IO.File]::WriteAllText($srcFile, "$($lines -join "`n")`n")
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
        invoke-gh pr create --fill --head $baseRepoBranch --repo $srcOwnerAndRepo --base $ENV:GITHUB_REF_NAME
        invoke-git checkout $algoBranch
    }
    else {
        invoke-git push $serverUrl
    }
}
finally {
    set-location $oldPath
}
