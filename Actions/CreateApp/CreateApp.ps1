Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects", Mandatory = $false)]
    [string] $project = '.',
    [ValidateSet("PTE", "AppSource App" , "Test App", "Performance Test App")]
    [Parameter(HelpMessage = "Type of app to add (PTE, AppSource App, Test App)", Mandatory = $true)]
    [string] $type,
    [Parameter(HelpMessage = "App Name", Mandatory = $true)]
    [string] $name,
    [Parameter(HelpMessage = "Publisher", Mandatory = $true)]
    [string] $publisher,
    [Parameter(HelpMessage = "ID range", Mandatory = $true)]
    [string] $idrange,
    [Parameter(HelpMessage = "Include Sample Code?", Mandatory = $false)]
    [bool] $sampleCode,
    [Parameter(HelpMessage = "Include Sample BCPT Suite?", Mandatory = $false)]
    [bool] $sampleSuite,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $directCommit
)

$tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $serverUrl, $branch = CloneIntoNewFolder -actor $actor -token $token -updateBranch $updateBranch -DirectCommit $directCommit -newBranchPrefix "create-$($type.replace(' ','-').ToLowerInvariant())"
    $baseFolder = (Get-Location).Path
    DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    import-module (Join-Path -path $PSScriptRoot -ChildPath "AppHelper.psm1" -Resolve)
    Write-Host "Template type : $type"

    # Check parameters
    if (-not $publisher) {
        throw "A publisher must be specified."
    }

    if (-not $name) {
        throw "An extension name must be specified."
    }

    $ids = ConfirmIdRanges -templateType $type -idrange $idrange

    CheckAndCreateProjectFolder -project $project
    $projectFolder = (Get-Location).Path

    if ($type -eq "Performance Test App") {
        try {
            $settings = ReadSettings -baseFolder $baseFolder -project $project
            $settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotIssueWarnings
            $folders = Download-Artifacts -artifactUrl $settings.artifact -includePlatform
            $sampleApp = Join-Path $folders[0] "Applications.*\Microsoft_Performance Toolkit Samples_*.app"
            if (Test-Path $sampleApp) {
                $sampleApp = (Get-Item -Path $sampleApp).FullName
            }
            else {
                $sampleApp = Join-Path $folders[1] "Applications\testframework\performancetoolkit\Microsoft_Performance Toolkit Samples.app"
            }
            if (!(Test-Path -Path $sampleApp)) {
                throw "Could not locate sample app for the Business Central version"
            }

            Extract-AppFileToFolder -appFilename $sampleApp -generateAppJson -appFolder $tmpFolder
        }
        catch {
            throw "Unable to create performance test app. Error was $($_.Exception.Message)"
        }
    }

    $orgfolderName = $name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $folderName = GetUniqueFolderName -baseFolder $projectFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "Folder $orgFolderName already exists in the repo, folder name $folderName will be used instead."
    }

    # Modify .AL-Go\settings.json
    try {
        $settingsJsonFile = Join-Path $projectFolder $ALGoSettingsFile
        $SettingsJson = Get-Content $settingsJsonFile -Encoding UTF8 | ConvertFrom-Json
        'appFolders','testFolders','bcptTestFolders' | ForEach-Object {
            if (-not ($settingsJson.PSObject.Properties.Name -eq $_)) {
                $SettingsJson | Add-Member -MemberType NoteProperty -Name $_ -Value @()
            }
        }
        if (@($settingsJson.appFolders)+@($settingsJson.testFolders)+@($settingsJson.bcptTestFolders)) {
            if ($type -eq "Performance Test App") {
                if ($SettingsJson.bcptTestFolders -notcontains $foldername) {
                    $SettingsJson.bcptTestFolders += @($folderName)
                }
            }
            elseif ($type -eq "Test App") {
                if ($SettingsJson.testFolders -notcontains $foldername) {
                    $SettingsJson.testFolders += @($folderName)
                }
            }
            else {
                if ($SettingsJson.appFolders -notcontains $foldername) {
                    $SettingsJson.appFolders += @($folderName)
                }
            }
            $SettingsJson | Set-JsonContentLF -Path $settingsJsonFile
        }
    }
    catch {
        throw "A malformed $ALGoSettingsFile is encountered.$([environment]::Newline) $($_.Exception.Message)"
    }

    $appVersion = "1.0.0.0"
    if ($settingsJson.PSObject.Properties.Name -eq "AppVersion") {
        $appVersion = "$($settingsJson.AppVersion).0.0"
    }

    if ($type -eq "Performance Test App") {
        NewSamplePerformanceTestApp -destinationPath (Join-Path $projectFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -sampleSuite $sampleSuite -idrange $ids -appSourceFolder $tmpFolder
    }
    elseif ($type -eq "Test App") {
        NewSampleTestApp -destinationPath (Join-Path $projectFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -idrange $ids
    }
    else {
        NewSampleApp -destinationPath (Join-Path $projectFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -idrange $ids
    }

    UpdateWorkspaces -projectFolder $projectFolder -appName $folderName

    Set-Location $baseFolder
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New $type ($Name)" -branch $branch | Out-Null
}
catch {
    throw
}
finally {
    if (Test-Path $tmpFolder) {
        Remove-Item $tmpFolder -Recurse -Force
    }
}
