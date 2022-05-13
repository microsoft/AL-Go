Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects (* for all projects)", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Updated Version Number. Use Major.Minor for absolute change, use +Major.Minor for incremental change.", Mandatory = $true)]
    [string] $versionnumber,
    [Parameter(HelpMessage = "Direct commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = $null

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    $repoBaseFolder = (Get-Location).path
    $BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $repoBaseFolder

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0076' -parentTelemetryScopeJson $parentTelemetryScopeJson
    
    $addToVersionNumber = "$versionnumber".StartsWith('+')
    if ($addToVersionNumber) {
        $versionnumber = $versionnumber.Substring(1)
    }
    try {
        $newVersion = [System.Version]"$($versionnumber).0.0"
    }
    catch {
        throw "Version number ($versionnumber) is malformed. A version number must be structured as <Major>.<Minor> or +<Major>.<Minor>"
    }

    if (!$project) { $project = '.' }

    if ($project -ne '.') {
        $projects = @(Get-Item -Path "$project\.AL-Go\Settings.json" | ForEach-Object { ($_.FullName.Substring((Get-Location).Path.Length).Split('\'))[1] })
        if ($projects.Count -eq 0) {
            if ($project -eq '*') {
                $projects = @( '.' )
            }
            else {
                throw "Project folder $project not found"
            }
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
                if ((!$addToVersionNumber) -and $newVersion -le $oldVersion) {
                    throw "The new version number ($($newVersion.Major).$($newVersion.Minor)) must be larger than the old version number ($($oldVersion.Major).$($oldVersion.Minor))"
                }
                $repoVersion = $newVersion
                if ($addToVersionNumber) {
                    $repoVersion = [System.Version]"$($newVersion.Major+$oldVersion.Major).$($newVersion.Minor+$oldVersion.Minor).0.0"
                }
                $settingsJson.RepoVersion = "$($repoVersion.Major).$($repoVersion.Minor)"
            }
            else {
                $repoVersion = $newVersion
                if ($addToVersionNumber) {
                    $repoVersion = [System.Version]"$($newVersion.Major+1).$($newVersion.Minor).0.0"
                }
                Add-Member -InputObject $settingsJson -NotePropertyName "RepoVersion" -NotePropertyValue "$($repoVersion.Major).$($repoVersion.Minor)"
            }
            $useRepoVersion = (($settingsJson.PSObject.Properties.Name -eq "VersioningStrategy") -and (($settingsJson.VersioningStrategy -band 16) -eq 16))
            $settingsJson
            $settingsJson | ConvertTo-Json -Depth 99 | Set-Content "$project\$ALGoSettingsFile" -Encoding UTF8
        }
        catch {
            throw "Settings file $project\$ALGoSettingsFile is malformed.$([environment]::Newline) $($_.Exception.Message)."
        }

        $folders = @('appFolders', 'testFolders' | ForEach-Object { if ($SettingsJson.PSObject.Properties.Name -eq $_) { $settingsJson."$_" } })
        if (-not ($folders)) {
            $folders = Get-ChildItem -Path $project -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'app.json') } | ForEach-Object { $_.Name }
        }
        $folders | ForEach-Object {
            Write-Host "Modifying app.json in folder $project\$_"
            $appJsonFile = Join-Path "$project\$_" "app.json"
            if (Test-Path $appJsonFile) {
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    $oldVersion = [System.Version]$appJson.Version
                    if ($useRepoVersion) {
                        $appVersion = $repoVersion
                    }
                    elseif ($addToVersionNumber) {
                        $appVersion = [System.Version]"$($newVersion.Major+$oldVersion.Major).$($newVersion.Minor+$oldVersion.Minor).0.0"
                    }
                    else {
                        $appVersion = $newVersion
                    }
                    $appJson.Version = "$appVersion"
                    $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile -Encoding UTF8
                }
                catch {
                    throw "Application manifest file($appJsonFile) is malformed."
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
