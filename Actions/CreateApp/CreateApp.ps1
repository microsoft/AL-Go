Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the Telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScope, 
    [Parameter(HelpMessage = "Specifies the event Id in the telemetry", Mandatory = $false)]
    [string] $telemetryEventId,    
    [ValidateSet("PTE", "AppSource App" , "Test App")]
    [Parameter(HelpMessage = "Type of app to add (Per Tenant Extension, AppSource App, Test App)", Mandatory = $true)]
    [string] $type,
    [Parameter(HelpMessage = "App Name", Mandatory = $true)]
    [string] $name,
    [Parameter(HelpMessage = "Publisher", Mandatory = $true)]
    [string] $publisher,
    [Parameter(HelpMessage = "ID range", Mandatory = $true)]
    [string] $idrange,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot "..\Helpers\AL-Go-Helper.ps1")
$BcContainerHelperPath = DownloadAndImportBcContainerHelper 
import-module (Join-Path -path $PSScriptRoot -ChildPath "..\Helpers\TelemetryHelper.psm1" -Resolve)

$telemetryScope = CreateScope -eventId $telemetryEventId -parentTelemetryScope $parentTelemetryScope

try {
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

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch

    $baseFolder = Get-Location
    $orgfolderName = $name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "$orgFolderName already exists as a folder in the repo, using $folderName instead"
    }

    # Modify .github\go\settings.json
    try {
        $settingsJsonFile = Join-Path $baseFolder $ALGoSettingsFile
        $SettingsJson = Get-Content $settingsJsonFile | ConvertFrom-Json
        if ($type -eq "Test App") {
            if ($SettingsJson.testFolders -notcontains $foldername) {
                $SettingsJson.testFolders += @($folderName)
            }
        }
        else {
            if ($SettingsJson.appFolders -notcontains $foldername) {
                $SettingsJson.appFolders += @($folderName)
            }
        }
        $SettingsJson | ConvertTo-Json -Depth 99 | Set-Content -Path $settingsJsonFile
    }
    catch {
        throw "A malformed $ALGoSettingsFile is encountered. Error: $($_.Exception.Message)"
    }

    $appVersion = "1.0.0.0"
    if ($settingsJson.PSObject.Properties.Name -eq "AppVersion") {
        $appVersion = "$($settingsJson.AppVersion).0.0"
    }

    if ($type -eq "Test App") {
        New-SampleTestApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -idrange $ids 
    }
    else {
        New-SampleApp -destinationPath (Join-Path $baseFolder $folderName) -name $name -publisher $publisher -version $appVersion -idrange $ids 
    }

    Update-WorkSpaces -baseFolder $baseFolder -appName $folderName
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New $type ($Name)" -branch $branch

    TrackTrace -telemetryScope $telemetryScope

}
catch {
    OutputError -message "Adding a new app failed due to $($_.Exception.Message)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    # Cleanup
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}