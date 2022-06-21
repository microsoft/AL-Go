Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
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
    [Parameter(HelpMessage = "Include Sample Code (Y/N)", Mandatory = $false)]
    [bool] $sampleCode,
    [Parameter(HelpMessage = "Include Sample BCPT Suite (Y/N)", Mandatory = $false)]
    [bool] $sampleSuite,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null
$tmpFolder = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    $repoBaseFolder = (Get-Location).Path
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $repoBaseFolder

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0072' -parentTelemetryScopeJson $parentTelemetryScopeJson
    
    import-module (Join-Path -path $PSScriptRoot -ChildPath "AppHelper.psm1" -Resolve)
    Write-Host "Template type : $type"

    # Check parameters
    if (-not $publisher) {
        throw "A publisher must be specified."
    }

    if (-not $name) {
        throw "An extension name must be specified."
    }

    $ids = Confirm-IdRanges -templateType $type -idrange $idrange

    CheckAndCreateProjectFolder -project $project
    $baseFolder = (Get-Location).Path

    if ($type -eq "Performance Test App") {
        try {
            $settings = ReadSettings -baseFolder $baseFolder -repoName $env:GITHUB_REPOSITORY -workflowName $env:GITHUB_WORKFLOW
            $settings = AnalyzeRepo -settings $settings -token $token -baseFolder $repoBaseFolder -project $project -doNotIssueWarnings
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
    $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "Folder $orgFolderName already exists in the repo, folder name $folderName will be used instead."
    }

    # Modify .AL-Go\settings.json
    try {
        $settingsJsonFile = Join-Path $baseFolder $ALGoSettingsFile
        $SettingsJson = Get-Content $settingsJsonFile -Encoding UTF8 | ConvertFrom-Json
        if (@($settingsJson.appFolders)+@($settingsJson.testFolders)) {
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
            $SettingsJson | ConvertTo-Json -Depth 99 | Set-Content -Path $settingsJsonFile -Encoding UTF8
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
        New-SamplePerformanceTestApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -sampleSuite $sampleSuite -idrange $ids -appSourceFolder $tmpFolder
    }
    elseif ($type -eq "Test App") {
        New-SampleTestApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -idrange $ids
    }
    else {
        New-SampleApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -sampleCode $sampleCode -idrange $ids 
    }

    Update-WorkSpaces -baseFolder $baseFolder -appName $folderName

    Set-Location $repoBaseFolder
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New $type ($Name)" -branch $branch

    TrackTrace -telemetryScope $telemetryScope

}
catch {
    OutputError -message "CreateApp action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
    if (Test-Path $tmpFolder) {
        Remove-Item $tmpFolder -Recurse -Force
    }
}
