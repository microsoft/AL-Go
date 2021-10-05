Param(
    [string] $actor,
    [string] $token,
    [string] $type,
    [string] $publisher,
    [string] $name,
    [string] $idrange,
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    Write-Host "type is $type"
    $types = @("Per Tenant Extension", "AppSource App", "Test App")
    if ($types -notcontains $type) {
        OutputError -message "type must be one of $($types -join ", ")"
        exit
    }

    # Check parameters
    if (-not $publisher) {
        OutputError -message "Publisher not specified"
        exit
    }

    if (-not $name) {
        OutputError -message "Name not specified"
        exit
    }

    if ($type -eq "Per Tenant Extension") {
        $ids = $idrange.Replace('..', '-').Split("-")
        if ($ids.Count -ne 2 -or ([int](stringToInt($ids[0])) -lt 50000) -or ([int](stringToInt($ids[0])) -gt 99999) -or ([int](stringToInt($ids[1])) -lt 50000) -or ([int](stringToInt($ids[1])) -gt 99999) -or ([int](stringToInt($ids[0])) -gt [int](stringToInt($ids[1])))) { 
            OutputError -message "IdRange should be formattet as fromid..toid, and the id range must be in 50000 and 99999"
            exit
        }
    }
    elseif ($type -eq "AppSource App") {
        $ids = $idrange.Replace('..', '-').Split("-")
        if ($ids.Count -ne 2 -or ([int](stringToInt($ids[0])) -lt 100000) -or ([int](stringToInt($ids[1])) -lt 100000) -or ([int](stringToInt($ids[0])) -gt [int](stringToInt($ids[1])))) { 
            OutputError -message "IdRange should be formattet as fromid..toid, and the id range must not be in 50000 and 99999"
            exit
        }
    }
    else {
        # Test App
        $ids = $idrange.Replace('..', '-').Split("-")
        if ($ids.Count -ne 2 -or ([int](stringToInt($ids[0])) -lt 50000) -or ([int](stringToInt($ids[1])) -lt 50000) -or ([int](stringToInt($ids[0])) -gt [int](stringToInt($ids[1])))) { 
            OutputError -message "IdRange should be formattet as fromid..toid, and the id range must be above 50000"
            exit
        }
    }

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch

    $baseFolder = Get-Location
    $orgfolderName = $name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "$orgFolderName already exists as a folder in the repo, using $folderName instead"
    }

    $templatePath = Join-Path $PSScriptRoot $type

    # Modify .github\AL-Go\settings.json
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
        OutputError -message "$ALGoSettingsFile is wrongly formatted. Error is $($_.Exception.Message)"
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
            OutputError "$workspaceFileName is wrongly formattet. Error is $($_.Exception.Message)"
            exit
        }
    }

    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New $type ($Name)" -branch $branch
}
catch {
    OutputError -message "Couldn't add an app. Error was $($_.Exception.Message)"
}