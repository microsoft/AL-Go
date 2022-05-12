Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Direct Download Url of .app or .zip file", Mandatory = $true)]
    [string] $url,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

function getfiles {
    Param(
        [string] $url
    )

    $path = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString()).app"
    Download-File -sourceUrl $url -destinationFile $path
    if (!(Test-Path -Path $path)) {
        throw "could not download the file."
    }

    expandfile -path $path
    Remove-Item $path -Force -ErrorAction SilentlyContinue
}

function expandfile {
    Param(
        [string] $path
    )

    if ([string]::new([char[]](Get-Content $path -Encoding byte -TotalCount 2)) -eq "PK") {
        # .zip file
        $destinationPath = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString())"
        Expand-7zipArchive -path $path -destinationPath $destinationPath
    
        $directoryInfo = Get-ChildItem $destinationPath | Measure-Object
        if ($directoryInfo.count -eq 0) {
            throw "The file is empty or malformed."
        }      

        $appFolders = @()
        if (Test-Path (Join-Path $destinationPath 'app.json')) {
            $appFolders += @($destinationPath)
        }
        Get-ChildItem $destinationPath -Directory -Recurse | Where-Object { Test-Path -Path (Join-Path $_.FullName 'app.json') } | ForEach-Object {
            if (!($appFolders -contains $_.Parent.FullName)) {
                $appFolders += @($_.FullName)
            }
        }
        $appFolders | ForEach-Object {
            $newFolder = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString())"
            write-Host "$_ -> $newFolder"
            Move-Item -Path $_ -Destination $newFolder -Force
            Write-Host "done"
            $newFolder
        }
        Get-ChildItem $destinationPath -include @("*.zip", "*.app") -Recurse | ForEach-Object {
            expandfile $_.FullName
        }
        Remove-Item -Path $destinationPath -Force -Recurse -ErrorAction SilentlyContinue
    }
    elseif ([string]::new([char[]](Get-Content $path -Encoding byte -TotalCount 4)) -eq "NAVX") {
        $destinationPath = Join-Path $env:TEMP "$([Guid]::NewGuid().ToString())"
        Extract-AppFileToFolder -appFilename $path -appFolder $destinationPath -generateAppJson
        $destinationPath        
    }
    else {
        throw "The provided url cannot be extracted. The url might be wrong or the file is malformed."
    }
}

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
    $telemetryScope = CreateScope -eventId 'DO0070' -parentTelemetryScopeJson $parentTelemetryScopeJson 

    $type = "PTE"
    Write-Host "Reading $RepoSettingsFile"
    $settingsJson = Get-Content $RepoSettingsFile -Encoding UTF8 | ConvertFrom-Json
    if ($settingsJson.PSObject.Properties.Name -eq "type") {
        $type = $settingsJson.Type
    }

    CheckAndCreateProjectFolder -project $project
    $baseFolder = (Get-Location).path

    Write-Host "Reading $ALGoSettingsFile"
    $settingsJson = Get-Content $ALGoSettingsFile -Encoding UTF8 | ConvertFrom-Json
    if ($settingsJson.PSObject.Properties.Name -eq "type") {
        $type = $settingsJson.Type
    }

    $appNames = @()
    getfiles -url $url | ForEach-Object {
        $appFolder = $_
        "?Content_Types?.xml", "MediaIdListing.xml", "navigation.xml", "NavxManifest.xml", "DocComments.xml", "SymbolReference.json" | ForEach-Object {
            Remove-Item (Join-Path $appFolder $_) -Force -ErrorAction SilentlyContinue
        }
        $appJson = Get-Content (Join-Path $appFolder "app.json") -Encoding UTF8 | ConvertFrom-Json
        $appNames += @($appJson.Name)

        $ranges = @()
        if ($appJson.PSObject.Properties.Name -eq "idRanges") {
            $ranges += $appJson.idRanges
        }
        if ($appJson.PSObject.Properties.Name -eq "idRange") {
            $ranges += @($appJson.idRange)
        }
        
        $ttype = ""
        $ranges | Select-Object -First 1 | ForEach-Object {
            if ($_.from -lt 100000 -and $_.to -lt 100000) {
                $ttype = "PTE"
            }
            else {
                $ttype = "AppSource App" 
            }
        }
        
        if ($appJson.PSObject.Properties.Name -eq "dependencies") {
            $appJson.dependencies | ForEach-Object {
                if ($_.PSObject.Properties.Name -eq "AppId") {
                    $id = $_.AppId
                }
                else {
                    $id = $_.Id
                }
                if ($testRunnerApps.Contains($id)) { 
                    $ttype = "Test App"
                }
            }
        }

        if ($ttype -ne "Test App") {
            Get-ChildItem -Path $appFolder -Filter "*.al" -Recurse | ForEach-Object {
                $alContent = (Get-Content -Path $_.FullName -Encoding UTF8) -join "`n"
                if ($alContent -like "*codeunit*subtype*=*test*[test]*") {
                    $ttype = "Test App"
                }
            }
        }

        if ($ttype -ne "Test App" -and $ttype -ne $type) {
            OutputWarning -message "According to settings, repository is for apps of type $type. The app you are adding seams to be of type $ttype"
        }

        $appFolders = Get-ChildItem -Path $appFolder -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'app.json') }
        if (-not $appFolders) {
            $appFolders = @($appFolder)
            # TODO: What to do about the über app.json - another workspace? another setting?
        }

        $orgfolderName = $appJson.name.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
        $folderName = GetUniqueFolderName -baseFolder $baseFolder -folderName $orgfolderName
        if ($folderName -ne $orgfolderName) {
            OutputWarning -message "$orgFolderName already exists as a folder in the repo, using $folderName instead"
        }

        Move-Item -Path $appFolder -Destination $baseFolder -Force
        Rename-Item -Path ([System.IO.Path]::GetFileName($appFolder)) -NewName $folderName
        $appFolder = Join-Path $baseFolder $folderName

        Get-ChildItem $appFolder -Filter '*.*' -Recurse | ForEach-Object {
            if ($_.Name.Contains('%20')) {
                Rename-Item -Path $_.FullName -NewName $_.Name.Replace('%20', ' ')
            }
        }

        $appFolders | ForEach-Object {
            # Modify .AL-Go\settings.json
            try {
                $settingsJsonFile = Join-Path $baseFolder $ALGoSettingsFile
                $SettingsJson = Get-Content $settingsJsonFile -Encoding UTF8 | ConvertFrom-Json
                if (@($settingsJson.appFolders)+@($settingsJson.testFolders)) {
                    if ($ttype -eq "Test App") {
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
                throw "$ALGoSettingsFile is malformed. Error: $($_.Exception.Message)"
            }

            # Modify workspace
            Get-ChildItem -Path $baseFolder -Filter "*.code-workspace" | ForEach-Object {
                try {
                    $workspaceFileName = $_.Name
                    $workspaceFile = $_.FullName
                    $workspace = Get-Content $workspaceFile -Encoding UTF8 | ConvertFrom-Json
                    if (-not ($workspace.folders | Where-Object { $_.Path -eq $foldername })) {
                        $workspace.folders += @(@{ "path" = $foldername })
                    }
                    $workspace | ConvertTo-Json -Depth 99 | Set-Content -Path $workspaceFile -Encoding UTF8
                }
                catch {
                   throw "$workspaceFileName is malformed.$([environment]::Newline) $($_.Exception.Message)"
                }
            }
        }
    }
    Set-Location $repoBaseFolder
    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Add existing apps ($($appNames -join ', '))" -branch $branch

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    OutputError -message "Couldn't add an existing app.$([environment]::Newline) $($_.Exception.Message)"
    TrackException -telemetryScope $telemetryScope -errorRecord $_
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}
