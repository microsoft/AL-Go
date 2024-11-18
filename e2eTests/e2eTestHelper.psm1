$githubOwner = "githubOwner"
$token = "token"
$defaultRepository = "repo"
$defaultApplication = "22.0.0.0"
$defaultRuntime = "10.0"
$defaultPublisher = "MS Test"

Import-Module (Join-Path $PSScriptRoot "..\Actions\Github-Helper.psm1" -Resolve) -DisableNameChecking -Global
. (Join-Path $PSScriptRoot "..\Actions\AL-Go-Helper.ps1" -Resolve)

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
    $script:token = GetRealToken -token $token -repository "$githubOwner/.github"
    $script:defaultRepository = $repository

    if ($github) {
        invoke-git config --global user.email "$githubOwner@users.noreply.github.com"
        invoke-git config --global user.name "$githubOwner"
        invoke-git config --global hub.protocol https
        invoke-git config --global core.autocrlf false
        $ENV:GITHUB_TOKEN = ''
    }
    Write-Host "Authenticating with GitHub using token"
    $script:token | invoke-gh auth login --with-token
    if ($github) {
        $ENV:GITHUB_TOKEN = $script:token
    }
}

function Get-PlainText {
    Param(
        [parameter(ValueFromPipeline, Mandatory = $true)]
        [System.Security.SecureString] $SecureString
    )
    Process {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString);
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr);
        }
        finally {
            [Runtime.InteropServices.Marshal]::FreeBSTR($bstr);
        }
    }
}

function Add-PropertiesToJsonFile {
    Param(
        [string] $path,
        [hashTable] $properties,
        [switch] $commit,
        [switch] $wait
    )

    if ($wait -and $commit) {
        $headers = GetHeaders -token $token -repository "$($script:githubOwner)/.github"
        Write-Host "Get Previous runs"
        $url = "https://api.github.com/repos/$repository/actions/runs"
        $previousrunids = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'push' } | Select-Object -ExpandProperty id
        if ($previousrunids) {
            Write-Host "Previous runs: $($previousrunids -join ', ')"
        }
        else {
            Write-Host "No previous runs found"
        }
    }
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
        if ($wait) {
            while ($true) {
                Start-Sleep -Seconds 10
                $run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'push' } | Where-Object { $previousrunids -notcontains $_.id }
                if ($run) {
                    break
                }
                Write-Host "Run not started, waiting..."
            }
            WaitWorkflow -repository $repository -runid $run.id
            $run
        }
    }
}

function Remove-PropertiesFromJsonFile {
    Param(
        [string] $path,
        [string[]] $properties
    )

    Write-Host -ForegroundColor Yellow "`nRemove Properties from $([System.IO.Path]::GetFileName($path))"
    Write-Host "Properties"
    $properties | Out-Host

    $json = Get-Content $path -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable -recurse
    $keys = @($json.Keys)
    $keys | ForEach-Object {
        $key = $_
        if ($properties | Where-Object { $key -like $_ }) {
            $json.Remove($key)
        }
    }
    $json | Set-JsonContentLF -path $path
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

    $headers = GetHeaders -token $token -repository "$($script:githubOwner)/.github"
    WaitForRateLimit -headers $headers -displayStatus

    Write-Host "Get Workflows"
    $url = "https://api.github.com/repos/$repository/actions/workflows"
    $workflows = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflows
    $workflows | ForEach-Object { Write-Host "- $($_.Name)"}
    if (!$workflows) {
        Write-Host "No workflows found, waiting 60 seconds and retrying"
        Start-Sleep -seconds 60
        $workflows = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflows
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
    $previousrun = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.workflow_id -eq $workflow.id -and $_.event -eq 'workflow_dispatch' } | Select-Object -First 1
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
        $run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.workflow_id -eq $workflow.id -and $_.event -eq 'workflow_dispatch' } | Select-Object -First 1
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
    $headers = GetHeaders -token $token -repository "$($script:githubOwner)/.github"
    $url = "https://api.github.com/repos/$repository/actions/runs/$runid"
    $run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json)
    $log = InvokeWebRequest -Method Get -Headers $headers -Uri $run.logs_url
    $tempFileName = "$([System.IO.Path]::GetTempFileName()).zip"
    [System.IO.File]::WriteAllBytes($tempFileName, $log.Content)
    Expand-Archive -Path $tempFileName -DestinationPath $path
}

function CancelAllWorkflows {
    Param(
        [string] $repository,
        [switch] $noDelay
    )
    if (-not $noDelay.IsPresent) {
        Start-Sleep -Seconds 60
    }
    $runs = gh api /repos/$repository/actions/runs | ConvertFrom-Json
    foreach($run in $runs.workflow_runs) {
        Write-Host $run.name
        if ($run.status -eq 'in_progress') {
            Write-Host "Cancelling $($run.name) run $($run.id)"
            gh api --method POST /repos/$repository/actions/runs/$($run.id)/cancel | Out-Null
        }
    }
}

function WaitAllWorkflows {
    Param(
        [string] $repository,
        [switch] $noDelay,
        [switch] $noError,
        [int] $top = 999
    )
    if (-not $noDelay.IsPresent) {
        Start-Sleep -Seconds 60
    }
    $runs = gh api /repos/$repository/actions/runs | ConvertFrom-Json
    $workflowRuns = $runs.workflow_runs | Select-Object -First $top
    foreach($run in $workflowRuns) {
        WaitWorkflow -repository $repository -runid $run.id -noDelay -noError:$noError
    }
}

function WaitWorkflow {
    Param(
        [string] $repository,
        [string] $runid,
        [switch] $noDelay,
        [switch] $noError
    )

    $delay = !$noDelay.IsPresent
    if (!$repository) {
        $repository = $defaultRepository
    }
    $headers = GetHeaders -token $token -repository "$($script:githubOwner)/.github"
    $status = ""
    do {
        if ($delay) {
            Start-Sleep -Seconds 60
        }
        WaitForRateLimit -headers $headers
        $url = "https://api.github.com/repos/$repository/actions/runs/$runid"
        $run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url).Content | ConvertFrom-Json)
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
    if ($run.conclusion -ne "Success" -and $run.conclusion -ne "cancelled") {
        if (-not $noError.IsPresent) { throw "Workflow $($run.name), conclusion $($run.conclusion), url = $($run.html_url)" }
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
        "pageextension $objID ""CustListExt$name"" extends ""Customer List"""
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
    $waitMinutes = 0
    if ($github) {
        $waitMinutes = Get-Random -Minimum 0 -Maximum 4
    }
    $templateFolder = ''
    if ($template.Contains('|')) {
        # In order to run tests on the direct AL-Go Development branch, specify the folder in which the template is located after a | character in template
        # example: "https://github.com/freddydk/AL-Go@branch|Templates/Per Tenant Extension"
        $templateFolder = $template.Split('|')[1]
        $templateOwner = $template.Split('/')[3]
        $template = $template.Split('|')[0]
        $waitMinutes = 0 # Do not wait when running tests on direct AL-Go Development branch
    }
    if (!$template.Contains('@')) {
        $template += '@main'
    }
    $templateBranch = $template.Split('@')[1]
    $templateRepo = $template.Split('@')[0]

    $tempPath = [System.IO.Path]::GetTempPath()
    $path = Join-Path $tempPath ( [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetTempFileName()))
    New-Item $path -ItemType Directory | Out-Null
    Set-Location $path
    if ($waitMinutes) {
        Write-Host "Waiting $waitMinutes minutes"
        Start-Sleep -seconds ($waitMinutes*60)
    }
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
    Copy-Item (Join-Path (Get-Item "$tempRepoPath/*/$templateFolder").FullName '*') -Destination . -Recurse -Force
    Remove-Item -Path $tempRepoPath -Force -Recurse
    Remove-Item -Path $zipFileName -Force
    if ($templateFolder) {
        # This is a direct AL-Go development repository
        # Replace URL's + references to microsoft/AL-Go-Actions with $templateOwner/AL-Go/Actions
        Get-ChildItem -Path . -File -Recurse | ForEach-Object {
            $file = $_.FullName
            $lines = Get-Content -Encoding UTF8 -path $file

            # Replace URL's to actions repository first
            $regex = "^(.*)https:\/\/raw\.githubusercontent\.com\/microsoft\/AL-Go-Actions\/main(.*)$"
            $replace = "`${1}https://raw.githubusercontent.com/$($templateOwner)/AL-Go/$($templateBranch)/Actions`${2}"
            $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }

            # Replace AL-Go-Actions references
            $regex = "^(.*)microsoft\/AL-Go-Actions(.*)main(.*)$"
            $replace = "`${1}$($templateOwner)/AL-Go/Actions`${2}$($templateBranch)`${3}"
            $lines = $lines | ForEach-Object { $_ -replace $regex, $replace }

            $content = "$($lines -join "`n")`n"

            # Update Template references in test apps
            $content = $content.Replace('{TEMPLATEURL}', $template)
            $content = $content.Replace('https://github.com/microsoft/AL-Go-PTE@main', $template)
            $content = $content.Replace('https://github.com/microsoft/AL-Go-AppSource@main', $template)

            [System.IO.File]::WriteAllText($file, $content)
        }
    }

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
    if ($linux) {
        $runson = "ubuntu-latest"
        $shell = "pwsh"
    }

    if ($runson -ne "windows-latest" -or $shell -ne "powershell") {
        $repoSettings | Add-Member -MemberType NoteProperty -Name "runs-on" -Value $runson
        $repoSettings | Add-Member -MemberType NoteProperty -Name "shell" -Value $shell
        Get-ChildItem -Path '.\.github\workflows\*.yaml' | ForEach-Object {
            Write-Host $_.FullName
            $content = Get-ContentLF -Path $_.FullName
            $srcPattern = "runs-on: [ windows-latest ]`n"
            $replacePattern = "runs-on: [ $runson ]`n"
            $content = "$content`n".Replace($srcPattern, $replacePattern).TrimEnd("`n")
            $srcPattern = "shell: powershell`n"
            $replacePattern = "shell: $shell`n"
            $content = "$content`n".Replace($srcPattern, $replacePattern).TrimEnd("`n")
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
        [string] $commitMessage = "commitmessage"
    )

    invoke-git add *
    invoke-git commit --allow-empty -m "'$commitMessage'"
    invoke-git push
}

function MergePRandPull {
    Param(
        [string] $repository,
        [string] $branch = "main",
        [switch] $wait
    )

    if (!$repository) {
        $repository = $defaultRepository
    }

    Write-Host "Get Previous runs"
    $headers = GetHeaders -token $token -repository "$($script:githubOwner)/.github"
    $url = "https://api.github.com/repos/$repository/actions/runs"
    $previousrunids = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'push' } | Select-Object -ExpandProperty id
    if ($previousrunids) {
        Write-Host "Previous runs: $($previousrunids -join ', ')"
    }
    else {
        Write-Host "No previous runs found"
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
    while ($true) {
        Start-Sleep -Seconds 10
        $run = ((InvokeWebRequest -Method Get -Headers $headers -Uri $url -retry).Content | ConvertFrom-Json).workflow_runs | Where-Object { $_.event -eq 'push' } | Where-Object { $previousrunids -notcontains $_.id }
        if ($run) {
            break
        }
        Write-Host "Run not started, waiting..."
    }
    if ($wait) {
        WaitWorkflow -repository $repository -runid $run.id
    }
    Write-Host "Merge commit run: $($run.id)"
    $run
    Pull -branch $branch
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
        try {
            $user = invoke-gh api user -silent -returnValue | ConvertFrom-Json
            Write-Host -ForegroundColor Yellow "`nRemoving repository $repository (user $($user.login))"
            $owner = $repository.Split("/")[0]
            if ($owner -eq $user.login) {
                # Package belongs to a user
                $ownerStr = "users/$owner"
            }
            else {
                # Package belongs to an organization
                $ownerStr = "orgs/$owner"
            }
            @((invoke-gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /$ownerStr/packages?package_type=nuget -silent -returnvalue -ErrorAction SilentlyContinue | ConvertFrom-Json)) | Where-Object { $_.PSObject.Properties.Name -eq 'repository' } | Where-Object { $_.repository.full_name -eq $repository } | ForEach-Object {
                Write-Host "+ package $($_.name)"
                # Pipe empty string into GH API --METHOD DELETE due to https://github.com/cli/cli/issues/3937
                '' | invoke-gh api --method DELETE -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /$ownerStr/packages/nuget/$($_.name) --input
            }
        }
        catch {
            Write-Host -ForegroundColor Red "Error removing packages"
            Write-Host -ForegroundColor Red $_.Exception.Message
        }
        invoke-gh repo delete $repository --yes | Out-Host
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
        [string] $expectedText,
        [switch] $isRegEx
    )

    DownloadWorkflowLog -repository $repository -runid $runid -path 'logs'
    $runPipelineLog = Get-Content -Path (Get-Item "logs/$jobName/*_$stepName.txt").FullName -encoding utf8 -raw
    if ($isRegEx) {
        $found = $runPipelineLog -match $expectedText
    }
    else {
        $found = $runPipelineLog.contains($expectedText, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ($found) {
        Write-Host "'$expectedText' found in the log for $jobName/$stepName as expected"
    }
    else {
        throw "Expected to find '$expectedText' in the log for $jobName/$stepName, but did not find it"
    }
    Remove-Item -Path 'logs' -Recurse -Force
}

. (Join-Path $PSScriptRoot "Workflows\RunAddExistingAppOrTestApp.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunCICD.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunCreateApp.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunDeployReferenceDocumentation.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunCreateOnlineDevelopmentEnvironment.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunCreateRelease.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunCreateTestApp.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunIncrementVersionNumber.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunPublishToEnvironment.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunUpdateAlGoSystemFiles.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunTestCurrent.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunTestNextMinor.ps1")
. (Join-Path $PSScriptRoot "Workflows\RunTestNextMajor.ps1")

. (Join-Path $PSScriptRoot "Test-Functions.ps1")
