Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects (* for all projects)", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "New version number (Major.Minor)", Mandatory = $true)]
    [string] $versionnumber,
    [Parameter(HelpMessage = "Direct commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper 
    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    
    $telemetryScope = CreateScope -eventId 'DO0076' -parentTelemetryScopeJson $parentTelemetryScopeJson
    
    try {
        $newVersion = [System.Version]"$($versionnumber).0.0"
    }
    catch {
        throw "Version number ($versionnumber) is malformed. A version number must be structured as <Major>.<Minor>"
    }

    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    if (!$project) { $project = '.' }

    if ($project -ne '.') {
        $projects = @(Get-Item -Path "$project\.AL-Go\Settings.json" | ForEach-Object { ($_.FullName.Substring((Get-Location).Path.Length).Split('\'))[1] })
        if ($projects.Count -eq 0) {
            throw "Project folder $project not found"
        }
    }
    else {
        $projects = @( '.' )
    }

    $projects | ForEach-Object {
        $project = $_
        try {
            Write-Host "Reading settings from $project\$ALGoSettingsFile"
            $settingsJson = Get-Content "$project\$ALGoSettingsFile" -Encoding UTF8 | ConvertFrom-Json
            if ($settingsJson.PSObject.Properties.Name -eq "RepoVersion") {
                $oldVersion = [System.Version]"$($settingsJson.RepoVersion).0.0"
                if ($newVersion -le $oldVersion) {
                    throw "The new version number ($($newVersion.Major).$($newVersion.Minor)) must be larger than the old version number ($($oldVersion.Major).$($oldVersion.Minor))"
                }
                $settingsJson.RepoVersion = "$($newVersion.Major).$($newVersion.Minor)"
            }
            else {
                Add-Member -InputObject $settingsJson -NotePropertyName "RepoVersion" -NotePropertyValue "$($newVersion.Major).$($newVersion.Minor)"
            }
            $modifyApps = (($settingsJson.PSObject.Properties.Name -eq "VersioningStrategy") -and (($settingsJson.VersioningStrategy -band 16) -eq 16))
            $settingsJson
            $settingsJson | ConvertTo-Json -Depth 99 | Set-Content "$project\$ALGoSettingsFile" -Encoding UTF8
        }
        catch {
            throw "Settings file $project\$ALGoSettingsFile is malformed.$([environment]::Newline) $($_.Exception.Message)."
        }

        if ($modifyApps) {
            Write-Host "Versioning strategy $($settingsJson.VersioningStrategy) is set. The version number in the apps will be changed."
            'appFolders', 'testFolders' | ForEach-Object {
                if ($SettingsJson.PSObject.Properties.Name -eq $_) {
                    $settingsJson."$_" | ForEach-Object {
                        Write-Host "Modifying app.json in folder $project\$_"
                        $appJsonFile = Join-Path "$project\$_" "app.json"
                        if (Test-Path $appJsonFile) {
                            try {
                                $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                                $appJson.Version = "$($newVersion.Major).$($newVersion.Minor).0.0"
                                $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile -Encoding UTF8
                            }
                            catch {
                                throw "Application manifest file($appJsonFile) is malformed."
                            }
                        }
                    }
                }
            }
        }
    }
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "New Version number $($newVersion.Major).$($newVersion.Minor)" -branch $branch

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "Increasing the version number failed. $([environment]::Newline) $($_.Exception.Message)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
