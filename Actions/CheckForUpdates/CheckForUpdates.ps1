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

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "yamlclass.ps1")

    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

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

    $RepoSettingsFile = ".github\AL-Go-Settings.json"
    if (Test-Path $RepoSettingsFile) {
        $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
    }
    else {
        $repoSettings = @{}
    }

    $updateSettings = $true
    if ($repoSettings.ContainsKey("TemplateUrl")) {
        if ($templateUrl.StartsWith('@')) {
            $templateUrl = "$($repoSettings.TemplateUrl.Split('@')[0])$templateUrl"
        }
        if ($repoSettings.TemplateUrl -eq $templateUrl) {
            $updateSettings = $false
        }
    }

    AddTelemetryProperty -telemetryScope $telemetryScope -key "templateUrl" -value $templateUrl

    $templateBranch = $templateUrl.Split('@')[1]
    $templateUrl = $templateUrl.Split('@')[0]

    $headers = @{
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }

    if ($templateUrl -ne "") {
        try {
            $templateUrl = $templateUrl -replace "https://www.github.com/","$ENV:GITHUB_API_URL/repos/" -replace "https://github.com/","$ENV:GITHUB_API_URL/repos/"
            Write-Host "Api url $templateUrl"
            $templateInfo = InvokeWebRequest -Headers $headers -Uri $templateUrl | ConvertFrom-Json
        }
        catch {
            throw "Could not retrieve the template repository. Error: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Api url $($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)"
        $repoInfo = InvokeWebRequest -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)" | ConvertFrom-Json
        if (!($repoInfo.PSObject.Properties.Name -eq "template_repository")) {
            OutputWarning -message "This repository wasn't built on a template repository, or the template repository is deleted. You must specify a template repository in the AL-Go settings file."
            exit
        }

        $templateInfo = $repoInfo.template_repository
    }

    $templateUrl = $templateInfo.html_url
    Write-Host "Using template from $templateUrl@$templateBranch"

    $headers = @{             
        "Accept" = "application/vnd.github.baptiste-preview+json"
    }
    $archiveUrl = $templateInfo.archive_url.Replace('{archive_format}','zipball').replace('{/ref}',"/$templateBranch")
    $tempName = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    InvokeWebRequest -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip"
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"
    
    $checkfiles = @(
        @{ "dstPath" = ".github\workflows"; "srcPath" = ".github\workflows"; "pattern" = "*"; "type" = "workflow" },
        @{ "dstPath" = ".github"; "srcPath" = ".github"; "pattern" = "*.copy.md"; "type" = "releasenotes" }
    )
    if (Test-Path (Join-Path $baseFolder ".AL-Go")) {
        $checkfiles += @(@{ "dstPath" = ".AL-Go"; "srcPath" = ".AL-Go"; "pattern" = "*.ps1"; "type" = "script" })
    }
    else {
        Get-ChildItem -Path $baseFolder -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".AL-Go") -PathType Container } | ForEach-Object {
            $checkfiles += @(@{ "dstPath" = Join-Path $_.Name ".AL-Go"; "srcPath" = ".AL-Go"; "pattern" = "*.ps1"; "type" = "script" })
        }
    }
    $updateFiles = @()

    $depth = 1
    if ($repoSettings.ContainsKey('useProjectDependencies') -and $repoSettings.useProjectDependencies) {
        if ($repoSettings.ContainsKey('Projects')) {
            $projects = $repoSettings.projects
        }
        else {
            $projects = @(Get-ChildItem -Path $ENV:GITHUB_WORKSPACE -Directory -Recurse -Depth 2 | Where-Object { Test-Path (Join-Path $_.FullName '.AL-Go\Settings.json') -PathType Leaf } | ForEach-Object { $_.FullName.Substring("$ENV:GITHUB_WORKSPACE".length+1) })
        }
        $buildAlso = @{}
        $buildOrder = @{}
        $projectDependencies = @{}
        AnalyzeProjectDependencies -basePath $ENV:GITHUB_WORKSPACE -projects $projects -buildOrder ([ref]$buildOrder) -buildAlso ([ref]$buildAlso) -projectDependencies ([ref]$projectDependencies)
        $depth = $buildOrder.Count
    }

    $checkfiles | ForEach-Object {
        $type = $_.type
        $srcPath = $_.srcPath
        $dstPath = $_.dstPath
        $dstFolder = Join-Path $baseFolder $dstPath
        $srcFolder = (Get-Item (Join-Path $tempName "*\$($srcPath)")).FullName
        Get-ChildItem -Path $srcFolder -Filter $_.pattern | ForEach-Object {
            $srcFile = $_.FullName
            $fileName = $_.Name
            $baseName = $_.BaseName
            $name = $type
            if ($type -eq "workflow") {
                $yaml = [Yaml]::Load($srcFile)
                $name = "$type $($yaml.get('name:').content[0].SubString(5).trim())"

                if ($baseName -ne "PullRequestHandler") {
                    $workflowScheduleKey = "$($baseName)Schedule"
                    if ($repoSettings.ContainsKey($workflowScheduleKey)) {
                        $yamlOn = $yaml.Get('on:/')
                        $yaml.Replace('on:/', $yamlOn.content+@('schedule:', "  - cron: '$($repoSettings."$workflowScheduleKey")'"))
                    }
                }

                if ($baseName -eq "CICD") {
                    if ($repoSettings.ContainsKey('CICDPushBranches')) {
                        $CICDPushBranches = $repoSettings.CICDPushBranches
                    }
                    elseif ($repoSettings.ContainsKey($workflowScheduleKey)) {
                        $CICDPushBranches = ''
                    }
                    else {
                        $CICDPushBranches = $defaultCICDPushBranches
                    }
                    if ($CICDPushBranches) {
                        $yaml.Replace('on:/push:/branches:', "branches: [ '$($cicdPushBranches -join "', '")' ]")
                    }
                    else {
                        $yaml.Replace('on:/push:',@())
                    }
                }

                if ($baseName -eq "PullRequestHandler") {
                    if ($repoSettings.ContainsKey('CICDPullRequestBranches')) {
                        $CICDPullRequestBranches = $repoSettings.CICDPullRequestBranches
                    }
                    else {
                        $CICDPullRequestBranches = $defaultCICDPullRequestBranches
                    }
                    $yaml.Replace('on:/pull_request:/branches:', "branches: [ '$($cicdPullRequestBranches -join "', '")' ]")
                }

                if ($baseName -ne "UpdateGitHubGoSystemFiles" -and $baseName -ne "PullRequestHandler") {
                    if ($repoSettings.ContainsKey("runs-on")) {
                        $yaml.ReplaceAll('runs-on: [ windows-latest ]', "runs-on: [ $($repoSettings."runs-on") ]")
                    }
                }

                if ($baseName -eq 'CICD' -or $baseName -eq 'Current' -or $baseName -eq 'NextMinor' -or $baseName -eq 'NextMajor') {
                    $yaml.Replace('env:/workflowDepth:',"workflowDepth: $depth")
                    if ($depth -gt 1) {
                        $initializationOutputs = $yaml.Get('jobs:/Initialization:/outputs:/')
                        $addOutput = @()
                        1..$depth | ForEach-Object {
                            $addOutput += @(
                              "projects$($_): `${{ steps.BuildOrder.outputs.Projects$($_)Json }}"
                              "projects$($_)Count: `${{ steps.BuildOrder.outputs.Projects$($_)Count }}"
                            )
                        }
                        $yaml.Replace('jobs:/Initialization:/outputs:/', $initializationOutputs.content+$addOutput)

                        $newBuild = @()
                        $build = $yaml.Get('jobs:/Build:/')
                        1..$depth | ForEach-Object {
                            if ($_ -eq 1) {
                                $needs = @('Initialization')
                                $if = "if: needs.Initialization.outputs.projects$($_)Count > 0"
                            }
                            else {
                                $newBuild += @('')
                                $needs = @('Initialization',"Build$($_-1)")
                                $if = "if: always() && (!cancelled()) && (needs.Build$($_-1).result == 'success' || needs.Build$($_-1).result == 'skipped') && needs.Initialization.outputs.projects$($_)Count > 0"
                            }
                            if ($depth -eq $_) {
                                $newBuild += @("Build:")
                            }
                            else {
                                $newBuild += @("Build$($_):")
                            }
                            $build.Replace('if:', $if)
                            $build.Replace('needs:', "needs: [ $($needs -join ', ') ]")
                            $build.Replace('strategy:/matrix:/project:',"project: `${{ fromJson(needs.Initialization.outputs.projects$($_)) }}")
                        
                            $build.content | ForEach-Object { $newBuild += @("  $_") }
                        }
                        $yaml.Replace('jobs:/Build:', $newBuild)
                    }
                }
                $srcContent = $yaml.content -join "`r`n"
            }
            else {
                $srcContent = (Get-Content -Path $srcFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
            }

                
            $dstFile = Join-Path $dstFolder $fileName
            if (Test-Path -Path $dstFile -PathType Leaf) {
                # file exists, compare
                $dstContent = (Get-Content -Path $dstFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
                if ($dstContent -ne $srcContent) {
                    Write-Host "Updated $name ($(Join-Path $dstPath $filename)) available"
                    $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
                }
            }
            else {
                # new file
                Write-Host "New $name ($(Join-Path $dstPath $filename)) available"
                $updateFiles += @{ "DstFile" = Join-Path $dstPath $filename; "content" = $srcContent }
            }
        }
    }
    $removeFiles = @()

    if (-not $update) {
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
        if ($updateSettings -or ($updateFiles) -or ($removeFiles)) {
            try {
                # URL for git commands
                $tempRepo = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
                New-Item $tempRepo -ItemType Directory | Out-Null
                Set-Location $tempRepo
                $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
                $url = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

                # Environment variables for hub commands
                $env:GITHUB_USER = $actor
                $env:GITHUB_TOKEN = $token

                # Configure git username and email
                invoke-git config --global user.email "$actor@users.noreply.github.com"
                invoke-git config --global user.name "$actor"

                # Configure hub to use https
                invoke-git config --global hub.protocol https

                # Clone URL
                invoke-git clone $url

                Set-Location -Path *
            
                if (!$directcommit) {
                    $branch = [System.IO.Path]::GetRandomFileName()
                    invoke-git checkout -b $branch
                }

                invoke-git status

                $templateUrl = "$templateUrl@$templateBranch"
                $RepoSettingsFile = ".github\AL-Go-Settings.json"
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
                    $repoSettings | Add-Member -MemberType NoteProperty -Name "templateUrl" -Value $templateUrl
                }
                $repoSettings | ConvertTo-Json -Depth 99 | Set-Content $repoSettingsFile -Encoding UTF8

                $releaseNotes = ""
                try {
                    $updateFiles | ForEach-Object {
                        $path = [System.IO.Path]::GetDirectoryName($_.DstFile)
                        if (-not (Test-Path -path $path -PathType Container)) {
                            New-Item -Path $path -ItemType Directory | Out-Null
                        }
                        if (([System.IO.Path]::GetFileName($_.DstFile) -eq "RELEASENOTES.copy.md") -and (Test-Path $_.DstFile)) {
                            $oldReleaseNotes = (Get-Content -Path $_.DstFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
                            while ($oldReleaseNotes) {
                                $releaseNotes = $_.Content
                                if ($releaseNotes.indexOf($oldReleaseNotes) -gt 0) {
                                    $releaseNotes = $releaseNotes.SubString(0, $releaseNotes.indexOf($oldReleaseNotes))
                                    $oldReleaseNotes = ""
                                }
                                else {
                                    $idx = $oldReleaseNotes.IndexOf("`r`n## ")
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
                        Set-Content -Path $_.DstFile -Encoding UTF8 -Value $_.Content
                    }
                }
                catch {}
                if ($releaseNotes -eq "") {
                    $releaseNotes = "No release notes available!"
                }
                $removeFiles | ForEach-Object {
                    Write-Host "Remove $_"
                    Remove-Item (Join-Path (Get-Location).Path $_) -Force
                }

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
    OutputError -message "CheckForUpdates action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
