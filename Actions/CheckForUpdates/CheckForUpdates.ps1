Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Settings from template repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"templateUrl": "", "templateBranch": ""}',
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

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    $baseFolder = $ENV:GITHUB_WORKSPACE

    if ($update -and -not $token) {
        OutputError "You need to add a secret called GHTOKENWORKFLOW containing a personal access token with permissions to modify Workflows. This is done by opening https://github.com/settings/tokens, Generate a new token and check the workflow scope."
        exit
    }

    $updateSettingsTemplate = $true
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable

    if ($templateUrl -eq "" -and $templateBranch -eq "") {
        $templateUrl = $settings.templateUrl
        $templateBranch = $settings.templateBranch
        $updateSettingsTemplate = $false
    }

    Set-Location $baseFolder
    $headers = @{             
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.baptiste-preview+json"
    }
    if ($templateUrl -ne "") {
        try {
            $templateUrl = $templateUrl -replace "https://www.github.com/","https://api.github.com/repos/" -replace "https://github.com/","https://api.github.com/repos/"
            Write-Host "Api url $templateUrl"
            $templateInfo = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $templateUrl | ConvertFrom-Json
        }
        catch {
            OutputError -message "Error reading template repository. Error was $($_.Exception.Message)"
            exit
        }
    }
    else {
        Write-Host "Api url $($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)"
        $repoInfo = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)" | ConvertFrom-Json
        if (!($repoInfo.PSObject.Properties.Name -eq "template_repository")) {
            OutputWarning -message "This repository wasn't built on a template repository, or the template repository has been deleted. You have to specify a template repository URL manually."
            exit
        }
        $templateInfo = $repoInfo.template_repository
    }

    if ($updateSettingsTemplate -and $templateUrl -eq $settings.templateUrl -and $templateBranch -eq $settings.templateBranch) {
        $updateSettingsTemplate = $false
    }

    $templateUrl = $templateInfo.html_url
    Write-Host "Using template from $templateUrl@$templateBranch"

    $headers = @{             
        "Accept"        = "application/vnd.github.baptiste-preview+json"
    }
    $archiveUrl = $templateInfo.archive_url.Replace('{archive_format}','zipball').replace('{/ref}','')
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
            $srcContent = (Get-Content -Path $srcFile -Raw).Replace("`r", "").Replace("`n", "`r`n")
            $name = $type
            if ($type -eq "workflow") {
                $srcContent.Split("`n") | Where-Object { $_ -like "name:*" } | Select-Object -First 1 | ForEach-Object {
                    if ($_ -match '^name:([^#]*)(#.*$|$)') { $name = "workflow '$($Matches[1].Trim())'" }
                }
            }
            $dstFile = Join-Path $dstFolder $fileName
            if (Test-Path -Path $dstFile -PathType Leaf) {
                # file exists, compare
                $dstContent = (Get-Content -Path $dstFile -Raw).Replace("`r", "").Replace("`n", "`r`n")
                if ($dstContent -ne $srcContent) {
                    Write-Host "Updated $name ($fileName) available"
                    $updateFiles += @{ "SrcFile" = "$srcFile"; "DstFile" = Join-Path $dstPath $filename }
                }
            }
            else {
                # new file
                Write-Host "New $name ($fileName) available"
                $updateFiles += @{ "SrcFile" = "$srcFile"; "DstFile" = Join-Path $dstPath $filename }
            }
        }
    }
    $removeFiles = @()
#    $dstFolder = Join-Path $ENV:GITHUB_WORKSPACE ".github\workflows"
#    $pathLength = "$ENV:GITHUB_WORKSPACE".Length
#    'ci.yaml','cd.yaml','registercustomerenvironment.yaml','ReleaseWorkflowTemplate.yaml.txt','ReleaseTo*-*-*-*-*-*-*.yaml' | ForEach-Object {
#        $removeFiles += @(Get-Item (Join-Path $dstFolder $_) -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($pathLength) })
#    }

    if (-not $update) {
        if (($updateFiles) -or ($removeFiles)) {
            OutputWarning -message "Updated AL-Go System Files are available for your repository, please run the Update AL-Go System Files workflow"
        }
        else {
            Write-Host "No updated AL-Go System Files are available"
        }
    }
    else {
        if ($updateSettingsTemplate -or ($updateFiles) -or ($removeFiles)) {
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

                $RepoSettingsFile = ".github\AL-Go-Settings.json"
                if (Test-Path $RepoSettingsFile) {
                    $repoSettings = Get-Content $repoSettingsFile | ConvertFrom-Json | ConvertTo-HashTable
                }
                else {
                    $repoSettings = @{}
                }
                $repoSettings.templateUrl = $templateUrl
                $repoSettings.templateBranch = $templateBranch
                $repoSettings | ConvertTo-Json -Depth 99 | Set-Content $repoSettingsFile

                $updateFiles | ForEach-Object {
                    $path = [System.IO.Path]::GetDirectoryName($_.DstFile)
                    if (-not (Test-Path -path $path -PathType Container)) {
                        New-Item -Path $path -ItemType Directory | Out-Null
                    }
                    Write-Host "Update $($_.DstFile)"
                    Copy-Item -Path $_.SrcFile -Destination $_.DstFile -Force
                }
                $removeFiles | ForEach-Object {
                    Write-Host "Remove $_"
                    Remove-Item (Join-Path (Get-Location).Path $_) -Force
                }

                invoke-git add *

                $message = "Updated AL-Go System Files"

                invoke-git commit -m "$message"

                if ($directcommit) {
                    invoke-git push $url
                }
                else {
                    invoke-git push -u $url $branch
                    invoke-hub pull-request -h $branch -m "$message"
                }
            }
            catch {
                if ($directCommit) {
                    OutputError -message "Error updating AL-Go System Files. The personal access token defined in the secret called GH_WORKFLOW_TOKEN might have expired or it doesn't have permission to update workflows?"
                    exit
                }
                else {
                    OutputError -message "Error creating PR for updating AL-Go System Files. The personal access token defined in the secret called GH_WORKFLOW_TOKEN might have expired or it doesn't have permission to update workflows?"
                    exit
                }
            }
        }
        else {
            OutputWarning "No updated AL-Go System Files are available"
        }
    }
}
catch {
    OutputError -message $_.Exception.Message
}