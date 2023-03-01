$githubOwner = "githubOwner"
$token = "token"
$defaultRepository = "repo"
$defaultApplication = "21.0.0.0"
$defaultRuntime = "10.0"
$defaultPublisher = "MS Test"

Import-Module (Join-Path $PSScriptRoot "..\Actions\Github-Helper.psm1" -Resolve) -DisableNameChecking -Global

function GetDefaultPublisher() {
    return $defaultPublisher
}

function SetTokenAndRepository {
    Param(
        [string] $githubOwner,
        [string] $token,
        [string] $repository,
        [switch] $github
    )

    $script:githubOwner = $githubOwner
    $script:token = $token
    $script:defaultRepository = $repository

    if ($github) {
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
}

function ConvertTo-HashTable {
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object,
        [switch] $recurse
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | ForEach-Object { 
            if ($recurse -and ($_.Value -is [PSCustomObject])) {
                $ht[$_.Name] = ConvertTo-HashTable $_.Value -recurse
            }
            else {
                $ht[$_.Name] = $_.Value
            }
        }
    }
    $ht
}

function Get-PlainText {
    Param(
        [parameter(ValueFromPipeline, Mandatory = $true)]
        [System.Security.SecureString] $SecureString
    )
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString);
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr);
    }
    finally {
        [Runtime.InteropServices.Marshal]::FreeBSTR($bstr);
    }
}

function Add-PropertiesToJsonFile {
    Param(
        [string] $path,
        [hashTable] $properties,
        [Switch] $commit
    )

    Write-Host -ForegroundColor Yellow "`nAdd Properties to $([System.IO.Path]::GetFileName($path))"
    Write-Host "Properties"
    $properties | Out-Host

    $json = Get-Content $path -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $properties.Keys | ForEach-Object {
        $json."$_" = $properties."$_"
    }
    $json | Set-JsonContentLF -path $path

    if ($commit) {
        CommitAndPush -commitMessage "Add properties to $([System.IO.Path]::GetFileName($path))"
    }
}


function DisplayTokenAndRepository {
    Write-Host "Token: $token"
    Write-Host "Repo: $defaultRepository"
}

function RunWorkflow {
    Param(
        [string] $name,
        [hashtable] $parameters = @{},
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    if (!$repository) {
        $repository = $defaultRepository
    }
    Write-Host -ForegroundColor Yellow "`nRun workflow $($name.Trim()) in $repository"
    if ($parameters -and $parameters.Count -gt 0) {
        Write-Host "Parameters:"
        Write-Host ($parameters | ConvertTo-Json)
    }

    $headers = @{ 
      "Accept" = "application/vnd.github.v3+json"
      "Authorization" = "token $token"
    }

    $rate = ((InvokeWebRequest -Headers $headers -Uri "https://api.github.com/rate_limit" -retry).Content | ConvertFrom-Json).rate
    $percent = [int]($rate.remaining*100/$rate.limit)
    Write-Host "$($rate.remaining) API calls remaining out of $($rate.limit) ($percent%)"
    if ($percent -lt 10) {
        $resetTimeStamp = ([datetime] '1970-01-01Z').AddSeconds($rate.reset)
        $waitTime = $resetTimeStamp.Subtract([datetime]::Now)
        Write-Host "Less than 10% API calls left, waiting for $($waitTime.TotalSeconds) seconds for limits to reset."
        Start-Sleep -seconds ($waitTime.TotalSeconds+1)
    }

    Write-Host "Get Workflows"
    $url = "https://api.github.com/repos/$repository/actions/workflows"
    $workflows = (InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry | ConvertFrom-Json).workflows
    $workflows | ForEach-Object { Write-Host "- $($_.Name)"}
    if (!$workflows) {
        Write-Host "No workflows found, waiting 60 seconds and retrying"
        Start-Sleep -seconds 60
        $workflows = (InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry | ConvertFrom-Json).workflows
        $workflows | ForEach-Object { Write-Host "- $($_.Name)"}
        if (!$workflows) {
            throw "No workflows found"
        }
    }
    $workflow = $workflows | Where-Object { $_.Name.Trim() -eq $name }
    if (!$workflow) {
        throw "Workflow $name not found"
    }

    Write-Host "Get Previous runs"
    $url = "https://api.github.com/repos/$repository/actions/runs"
    $previousrun = (InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry | ConvertFrom-Json).workflow_runs | Where-Object { $_.workflow_id -eq $workflow.id -and $_.event -eq 'workflow_dispatch' } | Select-Object -First 1
    if ($previousrun) {
        Write-Host "Previous run: $($previousrun.id)"
    }
    else {
        Write-Host "No previous run found"
    }
    
    Write-Host "Run workflow"
    $url = "https://api.github.com/repos/$repository/actions/workflows/$($workflow.id)/dispatches"
    Write-Host $url
    $body = @{
        "ref" = "refs/heads/$branch"
        "inputs" = $parameters
    }
    InvokeWebRequest -Method Post -Headers $headers -Uri $url -retry -Body ($body | ConvertTo-Json) | Out-Null

    Write-Host "Queuing"
    do {
        Start-Sleep -Seconds 10
        $url = "https://api.github.com/repos/$repository/actions/runs"
        $run = (InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry | ConvertFrom-Json).workflow_runs | Where-Object { $_.workflow_id -eq $workflow.id -and $_.event -eq 'workflow_dispatch' } | Select-Object -First 1
        Write-Host "."
    } until (($run) -and ((!$previousrun) -or ($run.id -ne $previousrun.id)))
    $runid = $run.id
    Write-Host "Run URL: https://github.com/$repository/actions/runs/$runid"
    if ($wait) {
        WaitWorkflow -repository $repository -runid $run.id
    }
    $run
}

function DownloadWorkflowLog {
    Param(
        [string] $repository,
        [string] $runid,
        [string] $path
    )

    if (!$repository) {
        $repository = $defaultRepository
    }
    $headers = @{ 
        "Accept" = "application/vnd.github.v3+json"
        "Authorization" = "token $token"
    }

    $url = "https://api.github.com/repos/$repository/actions/runs/$runid"
    $run = (InvokeWebRequest -Method Get -Headers $headers -Uri $url | ConvertFrom-Json)
    $log = InvokeWebRequest -Method Get -Headers $headers -Uri $run.logs_url
    $tempFileName = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllBytes($tempFileName, $log.Content)
    Expand-Archive -Path $tempFileName -DestinationPath $path
}

function WaitWorkflow {
    Param(
        [string] $repository,
        [string] $runid,
        [switch] $noDelay
    )

    $delay = !$noDelay.IsPresent
    if (!$repository) {
        $repository = $defaultRepository
    }
    $headers = @{ 
        "Accept" = "application/vnd.github.v3+json"
        "Authorization" = "token $token"
    }

    $status = ""
    do {
        if ($delay) {
            Start-Sleep -Seconds 60
        }
        $url = "https://api.github.com/repos/$repository/actions/runs/$runid"
        $run = (InvokeWebRequest -Method Get -Headers $headers -Uri $url | ConvertFrom-Json)
        if ($run.status -ne $status) {
            if ($status) { Write-Host }
            $status = $run.status
            Write-Host -NoNewline "$status"
        }
        Write-Host -NoNewline "."
        $delay = $true
    } while ($run.status -eq "queued" -or $run.status -eq "in_progress")
    Write-Host
    Write-Host $run.conclusion
    if ($run.conclusion -ne "Success") {
        throw "Workflow $name failed, url = $($run.html_url)"
    }
}

function SetRepositorySecret {
    Param(
        [string] $repository,
        [string] $name,
        [string] $value
    )

    if (!$repository) {
        $repository = $defaultRepository
    }
    Write-Host -ForegroundColor Yellow "`nSet Secret $name in $repository"
    invoke-gh secret set $name -b $value --repo $repository
}

function CreateNewAppInFolder {
    Param(
        [string] $folder,
        [string] $id = [GUID]::NewGUID().ToString(),
        [int] $objID = 50000,
        [string] $name,
        [string] $publisher = $defaultPublisher,
        [string] $version = "1.0.0.0",
        [string] $application = $defaultApplication,
        [string] $runtime = $defaultRuntime,
        [HashTable[]] $dependencies = @()
    )

    $al = @(
        "pageextension $objID CustListExt$name extends ""Customer List"""
        "{"
        "  trigger OnOpenPage();"
        "  begin"
        "    Message('App published: Hello $name!');"
        "  end;"
        "}")
    $appJson = [ordered]@{
        "id" = $id
        "name" = $name
        "version" = $version
        "publisher" = $publisher
        "dependencies" = $dependencies
        "application" = $application
        "runtime" = $runtime
        "idRanges" = @( @{ "from" = $objID; "to" = $objID } )
        "resourceExposurePolicy" = @{ "allowDebugging" = $true; "allowDownloadingSource" = $true; "includeSourceInSymbolFile" = $true }
    }
    $folder = Join-Path $folder $name
    New-Item -Path $folder -ItemType Directory | Out-Null
    $appJson | Set-JsonContentLF -Path (Join-Path $folder "app.json")
    $al -join "`n" | Set-ContentLF -Path (Join-Path $folder "$name.al")
    $id
}

function CreateAlGoRepository {
    Param(
        [switch] $github,
        [string] $repository,
        [string] $template = "",
        [string[]] $projects = @(),
        [string] $contentPath,
        [scriptBlock] $contentScript,
        [switch] $private,
        [switch] $linux,
        [string] $branch = "main",
        [hashtable] $addRepoSettings = @{}
    )

    if (!$repository) {
        $repository = $defaultRepository
    }
    if (!$template.Contains('@')) {
        $template += '@main'
    }
    $templateBranch = $template.Split('@')[1]
    $templateRepo = $template.Split('@')[0]

    $tempPath = [System.IO.Path]::GetTempPath()
    $path = Join-Path $tempPath ([GUID]::NewGuid().ToString())
    New-Item $path -ItemType Directory | Out-Null
    Set-Location $path
    if ($private) {
        Write-Host -ForegroundColor Yellow "`nCreating private repository $repository (based on $template)"
        invoke-gh repo create $repository --private --clone
    }
    else {
        Write-Host -ForegroundColor Yellow "`nCreating public repository $repository (based on $template)"
        invoke-gh repo create $repository --public --clone
    }
    Start-Sleep -seconds 10
    Set-Location '*'

    $templateUrl = "$templateRepo/archive/refs/heads/$templateBranch.zip"
    Write-Host "Downloading template from $templateUrl"
    $zipFileName = Join-Path $tempPath "$([GUID]::NewGuid().ToString()).zip"
    [System.Net.WebClient]::new().DownloadFile($templateUrl, $zipFileName)
    
    $tempRepoPath = Join-Path $tempPath ([GUID]::NewGuid().ToString())
    Expand-Archive -Path $zipFileName -DestinationPath $tempRepoPath
    Copy-Item (Join-Path (Get-Item "$tempRepoPath\*").FullName '*') -Destination . -Recurse -Force
    Remove-Item -Path $tempRepoPath -Force -Recurse
    Remove-Item -Path $zipFileName -Force
    if ($projects) {
        # Make Repo multi-project
        $projects | ForEach-Object {
            New-Item $_ -ItemType Directory | Out-Null
            Copy-Item '.AL-Go' -Destination $_ -Recurse -Force
        }
        Remove-Item '.AL-Go' -Force -Recurse
    }
    if ($contentPath) {
        Write-Host "Copy content from $contentPath"
        Copy-Item (Join-Path $contentPath "*") -Destination . -Recurse -Force
    }
    if ($contentScript) {
        & $contentScript -path (get-location).Path
    }
    $repoSettingsFile = ".github\AL-Go-Settings.json"
    $repoSettings = Get-Content $repoSettingsFile -Encoding UTF8 | ConvertFrom-Json
    $runson = "windows-latest"
    $shell = "powershell"
    if ($private) {
        $repoSettings | Add-Member -MemberType NoteProperty -Name "gitHubRunner" -Value "self-hosted"
        $repoSettings | Add-Member -MemberType NoteProperty -Name "gitHubRunnerShell" -Value "powershell"
        $runson = "self-hosted"
    }
    if ($linux) {
        $runson = "ubuntu-latest"
        $shell = "pwsh"
    }

    if ($runson -ne "windows-latest" -or $shell -ne "powershell") {
        $repoSettings | Add-Member -MemberType NoteProperty -Name "runs-on" -Value $runson
        $repoSettings | Add-Member -MemberType NoteProperty -Name "shell" -Value $shell
        Get-ChildItem -Path '.\.github\workflows\*.yaml' | Where-Object { $_.BaseName -ne "UpdateGitHubGoSystemFiles" -and $_.BaseName -ne "PullRequestHandler" } | ForEach-Object {
            Write-Host $_.FullName
            $content = Get-ContentLF -Path $_.FullName
            $srcPattern = "runs-on: [ windows-latest ]`n"
            $replacePattern = "runs-on: [ $runson ]`n"
            $content = $content.Replace($srcPattern, $replacePattern)
            $srcPattern = "shell: powershell`n"
            $replacePattern = "shell: $shell`n"
            $content = $content.Replace($srcPattern, $replacePattern)
            [System.IO.File]::WriteAllText($_.FullName, $content)
        }
    }
    # Disable telemetry AL-Go and BcContainerHelper telemetry when running end-2-end tests
    $repoSettings | Add-Member -MemberType NoteProperty -Name "MicrosoftTelemetryConnectionString" -Value ""
    $repoSettings | Set-JsonContentLF -path $repoSettingsFile
    if ($addRepoSettings.Keys.Count) {
        Add-PropertiesToJsonFile -path $repoSettingsFile -properties $addRepoSettings
    }

    invoke-git add *
    invoke-git commit --allow-empty -m 'init'
    invoke-git branch -M $branch
    if ($githubOwner -and $token) {
        invoke-git remote set-url origin "https://$($githubOwner):$token@github.com/$repository.git"
    }
    invoke-git push --set-upstream origin $branch
    if (!$github) {
        Start-Process "https://github.com/$repository/actions"
    }
    Start-Sleep -seconds 10
}

function Pull {
    Param(
        [string] $branch = "main"
    )

    invoke-git pull origin $branch
}

function CommitAndPush {
    Param(
        [string] $serverUrl,
        [string] $commitMessage = "commitmessage"
    )

    invoke-git add *
    invoke-git commit --allow-empty -m "'$commitMessage'"
    invoke-git push $serverUrl
}

function MergePRandPull {
    Param(
        [string] $repository,
        [string] $branch = "main"
    )

    if (!$repository) {
        $repository = $defaultRepository
    }
    $phs = @(invoke-gh -returnValue pr list --repo $repository)
    if ($phs.Count -eq 0) {
        throw "No Pull Request was created"
    }
    elseif ($phs.Count -gt 1) {
        throw "More than one Pull Request exists"
    }
    $prid = $phs.Split("`t")[0]
    Write-Host -ForegroundColor Yellow "`nMerge Pull Request $prid into repository $repository"
    invoke-gh pr merge $prid --squash --delete-branch --repo $repository | Out-Host
    Pull -branch $branch
    Start-Sleep -Seconds 30
}

function RemoveRepository {
    Param(
        [string] $repository,
        [string] $path = ""
    )

    if (!$repository) {
        $repository = $defaultRepository
    }
    if ($repository) {
        Write-Host -ForegroundColor Yellow "`nRemoving repository $repository"
        try {
            $owner = $repository.Split("/")[0]
            @((invoke-gh api -H "Accept: application/vnd.github+json" /orgs/$owner/packages?package_type=nuget -silent -returnvalue -ErrorAction SilentlyContinue | ConvertFrom-Json)) | Where-Object { $_.PSObject.Properties.Name -eq 'repository' } | Where-Object { $_.repository.full_name -eq $repository } | ForEach-Object {
                Write-Host "+ package $($_.name)"
                # Pipe empty string into GH API --METHOD DELETE due to https://github.com/cli/cli/issues/3937
                '' | invoke-gh api --method DELETE -H "Accept: application/vnd.github+json" /orgs/$owner/packages/nuget/$($_.name) --input -
            }
        }
        catch {
            Write-Host -ForegroundColor Red "Error removing packages"
            Write-Host -ForegroundColor Red $_.Exception.Message
        }
        invoke-gh repo delete $repository --confirm | Out-Host
    }

    if ($path) {
        if (-not $path.StartsWith("$([System.IO.Path]::GetTempPath())",[StringComparison]::InvariantCultureIgnoreCase)) {
            throw "$path is not temppath"
        }
        else {
            Set-Location ([System.IO.Path]::GetTempPath())
            Remove-Item $path -Recurse -Force
        }
    }
}

function Test-LogContainsFromRun {
    Param(
        [string] $repository,
        [string] $runid,
        [string] $jobName,
        [string] $stepName,
        [string] $expectedText
    )

    DownloadWorkflowLog -repository $repository -runid $runid -path 'logs'
    $runPipelineLog = Get-Content -Path (Get-Item "logs/$jobName/*_$stepName.txt").FullName -encoding utf8 -raw
    if ($runPipelineLog.contains($expectedText, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "'$expectedText' found in the log for $jobName/$stepName as expected"
    }
    else {
        throw "Expected to find '$expectedText' in the log for $jobName/$stepName, but did not find it"
    }
    Remove-Item -Path 'logs' -Recurse -Force
}

. (Join-Path $PSScriptRoot "Workflows\Run-AddExistingAppOrTestApp.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-CICD.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-CreateApp.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-CreateOnlineDevelopmentEnvironment.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-CreateRelease.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-CreateTestApp.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-IncrementVersionNumber.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-PublishToEnvironment.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-UpdateAlGoSystemFiles.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-TestCurrent.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-TestNextMinor.ps1")
. (Join-Path $PSScriptRoot "Workflows\Run-TestNextMajor.ps1")

. (Join-Path $PSScriptRoot "Test-Functions.ps1")
