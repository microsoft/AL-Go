Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "URL of the template repository (default is the template repository used to create the repository)", Mandatory = $false)]
    [string] $templateUrl = "",
    [Parameter(HelpMessage = "Branch in template repository to use for the update (default is the default branch)", Mandatory = $false)]
    [string] $templateBranch = "",
    [Parameter(HelpMessage = "Set this input to Y in order to update AL-Go System Files if needed", Mandatory = $false)]
    [bool] $update,
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
    $baseFolder = $ENV:GITHUB_WORKSPACE
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0071' -parentTelemetryScopeJson $parentTelemetryScopeJson

    if ($update -and -not $token) {
        throw "A personal access token with permissions to modify Workflows is needed. You must add a secret called GhTokenWorkflow containing a personal access token. You can Generate a new token from https://github.com/settings/tokens. Make sure that the workflow scope is checked."
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
            $templateInfo = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $templateUrl | ConvertFrom-Json
        }
        catch {
            throw "Could not retrieve the template repository. Error: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Api url $($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)"
        $repoInfo = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)" | ConvertFrom-Json
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
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip"
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"
    
    $checkfiles = @(@{ "dstPath" = ".github\workflows"; "srcPath" = ".github\workflows"; "pattern" = "*"; "type" = "workflow" })
    if (Test-Path (Join-Path $baseFolder ".AL-Go")) {
        $checkfiles += @(@{ "dstPath" = ".AL-Go"; "srcPath" = ".AL-Go"; "pattern" = "*.ps1"; "type" = "script" })
    }
    else {
        Get-ChildItem -Path $baseFolder -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".AL-Go") -PathType Container } | ForEach-Object {
            $checkfiles += @(@{ "dstPath" = Join-Path $_.Name ".AL-Go"; "srcPath" = ".AL-Go"; "pattern" = "*.ps1"; "type" = "script" })
        }
    }
    $updateFiles = @()

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
            $srcContent = (Get-Content -Path $srcFile -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n").Replace("`n", "`r`n")
            $name = $type
            if ($type -eq "workflow") {
                $srcContent.Split("`n") | Where-Object { $_ -like "name:*" } | Select-Object -First 1 | ForEach-Object {
                    if ($_ -match '^name:([^#]*)(#.*$|$)') { $name = "workflow '$($Matches[1].Trim())'" }
                }
            }

            $workflowScheduleKey = "$($baseName)Schedule"
            if ($repoSettings.ContainsKey($workflowScheduleKey)) {
                $srcPattern = "on:`r`n  workflow_dispatch:`r`n"
                $replacePattern = "on:`r`n  schedule:`r`n  - cron: '$($repoSettings."$workflowScheduleKey")'`r`n  workflow_dispatch:`r`n"
                $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
            }
            
            if ($baseName -ne "UpdateGitHubGoSystemFiles") {
                if ($repoSettings.ContainsKey("runs-on")) {
                    $srcPattern = "runs-on: [ windows-latest ]`r`n"
                    $replacePattern = "runs-on: [ $($repoSettings."runs-on") ]`r`n"
                    $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                    if (!($repoSettings.ContainsKey("gitHubRunner"))) {
                        $srcPattern = "runs-on: `${{ fromJson(needs.Initialization.outputs.githubRunner) }}`r`n"
                        $replacePattern = "runs-on: [ $($repoSettings."runs-on") ]`r`n"
                        $srcContent = $srcContent.Replace($srcPattern, $replacePattern)
                    }
                }
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
            Write-Host "Your repository runs on the latest version of AL-Go System."
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

                $updateFiles | ForEach-Object {
                    $path = [System.IO.Path]::GetDirectoryName($_.DstFile)
                    if (-not (Test-Path -path $path -PathType Container)) {
                        New-Item -Path $path -ItemType Directory | Out-Null
                    }
                    Write-Host "Update $($_.DstFile)"
                    Set-Content -Path $_.DstFile -Encoding UTF8 -Value $_.Content
                }
                $removeFiles | ForEach-Object {
                    Write-Host "Remove $_"
                    Remove-Item (Join-Path (Get-Location).Path $_) -Force
                }

                invoke-git add *

                $status = invoke-git status --porcelain=v1
                if ($status) {
                    $message = "Updated AL-Go System Files"

                    invoke-git commit --allow-empty -m "'$message'"

                    if ($directcommit) {
                        invoke-git push $url
                    }
                    else {
                        invoke-git push -u $url $branch
                        invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY
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
            OutputWarning "Your repository runs on the latest version of AL-Go System."
        }
    }

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message $_.Exception.Message
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
