Param(
    [string] $actor,
    [string] $token,
    [string][ValidateSet("Per Tenant Extension", "AppSource App", "Test App")] $type,
    [string] $publisher,
    [string] $name,
    [string] $idrange,
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0


$validRanges =@(
    {templateType = "Per Tenant Extension", startOfRange = 50000, endOfRange= 99999},
    {templateType = "AppSource App", startOfRange = 100000, endOfRange=  [int32]::MaxValue},
    {templateType = "Test App", startOfRange = 50000, endOfRange= [int32]::MaxValue}
    );
function ValidateIdRanges ([string] $templateType,[string]$idrange )  
{  
    $validRange = $validRanges |.where({$_.templateType -eq $templateType})
    $ids = $idrange.Replace('..', '-').Split("-")

    if ($ids.Count -ne 2 -or ([int](stringToInt($ids[0])) -lt $validRange.startOfRange) -or ([int](stringToInt($ids[0])) -gt $validRange.endOfRange) -or ([int](stringToInt($ids[1])) -lt $validRange.startOfRange) -or ([int](stringToInt($ids[1])) -gt $validRange.endOfRange) -or ([int](stringToInt($ids[0])) -gt [int](stringToInt($ids[1])))) { 
        OutputError -message "IdRange should be formattet as fromId..toId, and the Id range must be in $($validRange.startOfRange) and $($validRange.endOfRange)"
        exit
    }
}  

try {
    . (Join-Path $PSScriptRoot "..\GitHub-Go-Helper.ps1")

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

    ValidateIdRanges($type, $idrange)

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch

    $baseFolder = Get-Location
    $orgfolderName = $name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
    if ($folderName -ne $orgfolderName) {
        OutputWarning -message "$orgFolderName already exists as a folder in the repo, using $folderName instead"
    }

    $templatePath = Join-Path $PSScriptRoot $type

    # Modify .github\go\settings.json
    try {
        $settingsJsonFile = Join-Path $baseFolder $gitHubGoSettingsFile
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
        OutputError -message "A malformed $gitHubGoSettingsFile is encountered. Error: $($_.Exception.Message)"
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