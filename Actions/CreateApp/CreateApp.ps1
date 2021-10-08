Param(
    [string] $actor,
    [string] $token,
    [string][ValidateSet("PTE", "AppSource App" , "Test App")] $type,
    [string] $publisher,
    [string] $name,
    [string] $idrange,
    [bool] $directCommit
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

. (Join-Path -path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
import-module (Join-Path -path $PSScriptRoot -ChildPath "AppHelper.psm1" -Resolve)

try {
    Write-Host "Template type : $type"

    # Check parameters
    if (-not $publisher) {
        OutputError -message "A publisher must be specified."
        exit
    }

    if (-not $name) {
        OutputError -message "An extension name must be specified."
        exit
    }

    ValidateIdRanges -templateType $type -idrange $idrange
    $ids = $idrange.Replace('..', '-').Split("-")

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
#    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch

    $baseFolder = Get-Location
    $orgfolderName = $name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "$orgFolderName already exists as a folder in the repo, using $folderName instead"
    }

    $templatePath = Join-Path $PSScriptRoot $type

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
        OutputError -message "A malformed $ALGoSettingsFile is encountered. Error: $($_.Exception.Message)"
        exit
    }

    $appVersion = "1.0.0.0"
    if ($settingsJson.PSObject.Properties.Name -eq "AppVersion") {
        $appVersion = "$($settingsJson.AppVersion).0.0"
    }

    # Modify app.json
    $appJsonFile = Join-Path $templatePath "app.json"
    $appJson = Get-Content $appJsonFile | ConvertFrom-Json

    $appJson.id = [Guid]::NewGuid().ToString()
    $appJson.Publisher = $publisher
    $appJson.Name = $name
    $appJson.Version = $appVersion
    $appJson.idRanges[0].from = $ids[0]
    $appJson.idRanges[0].to = $ids[1]
    $appJson | ConvertTo-Json -Depth 99 | Set-Content -Path $appJsonFile

    $alFile = (Get-Item (Join-Path $templatePath "*.al")).FullName
    $al = Get-Content -Raw -path $alFile
    $al = $al.Replace('50100', $ids[0])
    Set-Content -Path $alFile -value $al

    Move-Item -path $templatePath -Destination (Join-Path $baseFolder $folderName)

    # Modify workspace
    Get-ChildItem -Path $baseFolder -Filter "*.code-workspace" | ForEach-Object {
        try {
            $workspaceFileName = $_.Name
            $workspaceFile = $_.FullName
            $workspace = Get-Content $workspaceFile | ConvertFrom-Json
            if (-not ($workspace.folders | Where-Object { $_.Path -eq $foldername })) {
                $workspace.folders += @(@{ "path" = $foldername })
            }
            $workspace | ConvertTo-Json -Depth 99 | Set-Content -Path $workspaceFile
        }
        catch {
            OutputError "Updating the workspace file $workspaceFileName failed due to: $($_.Exception.Message)"
            exit
        }
    }

    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New $type ($Name)" -branch $branch
}
catch {
    OutputError -message "Adding a new app failed due to $($_.Exception.Message)"
}