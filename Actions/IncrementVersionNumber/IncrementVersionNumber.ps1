Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "New Version Number (Major.Minor)", Mandatory = $true)]
    [string] $versionnumber,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

    try {
        $newVersion = [System.Version]"$($versionnumber).0.0"
    }
    catch {
        OutputError -message "Version number ($versionnumber) is wrongly formatted. Needs to be Major.Minor"
        exit
    }

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch

    try {
        Write-Host "Reading $ALGoSettingsFile"
        $settingsJson = Get-Content $ALGoSettingsFile -Encoding UTF8 | ConvertFrom-Json
        if ($settingsJson.PSObject.Properties.Name -eq "RepoVersion") {
            $oldVersion = [System.Version]"$($settingsJson.RepoVersion).0.0"
            if ($newVersion -le $oldVersion) {
                OutputError -message "New version number ($($newVersion.Major).$($newVersion.Minor)) needs to be larger than old version number ($($oldVersion.Major).$($oldVersion.Minor))"
                exit
            }
            $settingsJson.RepoVersion = "$($newVersion.Major).$($newVersion.Minor)"
        }
        else {
            Add-Member -InputObject $settingsJson -NotePropertyName "RepoVersion" -NotePropertyValue "$($newVersion.Major).$($newVersion.Minor)"
        }
        $modifyApps = (($settingsJson.PSObject.Properties.Name -eq "VersioningStrategy") -and (($settingsJson.VersioningStrategy -band 16) -eq 16))
        $settingsJson
        $settingsJson | ConvertTo-Json -Depth 99 | Set-Content $ALGoSettingsFile -Encoding UTF8
    }
    catch {
        OutputError "Settings file $ALGoSettingsFile, is wrongly formatted. Error is $($_.Exception.Message)."
        exit
    }

    if ($modifyApps) {
        Write-Host "Versioning strategy $($settingsJson.VersioningStrategy) means that the version number in apps will also be changed."
        'appFolders', 'testFolders' | ForEach-Object {
            if ($SettingsJson.PSObject.Properties.Name -eq $_) {
                $settingsJson."$_" | ForEach-Object {
                    Write-Host "Modifying app.json in folder $_"
                    $appJsonFile = Join-Path $_ "app.json"
                    if (Test-Path $appJsonFile) {
                        try {
                            $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                            $appJson.Version = "$($newVersion.Major).$($newVersion.Minor).0.0"
                            $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile -Encoding UTF8
                        }
                        catch {
                            throw "$appJsonFile is wrongly formatted."
                        }
                    }
                }
            }
        }
    }
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New Version number $($newVersion.Major).$($newVersion.Minor)" -branch $branch
}
catch {
    OutputError -message "Couldn't bump version number. Error was $($_.Exception.Message)"
}
