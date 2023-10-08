function RunningOnLinux {
    $isPsCore = $PSVersionTable.PSVersion -ge "6.0.0"
    return ($isPsCore -and $isLinux)
}

function FixBackslashes {
    Param(
        [string] $docfxPath
    )

    if (-not (RunningOnLinux)) {
        return
    }
    $allFiles = @(get-childitem -path "$docfxPath/*" -Recurse -File | ForEach-Object { $_.FullName })
    $allFiles | Where-Object { $_.Contains('\') } | ForEach-Object {
        $newName = $_.Replace('\','/')
        $folder = Split-Path -Path $newName -Parent
        if (-not (Test-Path $folder -PathType Container)) {
            New-Item -Path $folder -ItemType Directory | Out-Null
        }
        & cp $_ $newName
        & rm $_
    }
}
function DownloadAlDoc {
    if ("$ENV:aldocPath" -eq "") {
        Write-Host "Locating aldoc"
        $artifactUrl = Get-BCArtifactUrl -storageAccount bcinsider -type sandbox -country core -select Latest -accept_insiderEula
        Write-Host "Downloading aldoc"
        $folder = Download-Artifacts $artifactUrl
        $alLanguageVsix = Join-Path $folder '*.vsix' -Resolve
        $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        Copy-Item -Path $alLanguageVsix -Destination "$($tempFolder).zip"
        New-Item -Path $tempFolder -ItemType Directory | Out-Null
        Write-Host "Extracting aldoc"
        Expand-Archive -Path "$($tempFolder).zip" -DestinationPath $tempFolder -Force
        Remove-Item -Path "$($tempFolder).zip" -Force
        if (RunningOnLinux) {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/linux/aldoc'
            & /usr/bin/env sudo pwsh -command "& chmod +x $ENV:aldocPath"
        }
        else {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/win32/aldoc.exe'
        }

        Write-Host "Installing/Updating docfx"
        CmdDo -command dotnet -arguments @('tool','update','-g docfx')
    }
    $ENV:aldocPath
}

function SanitizeFileName([string] $filename) {
    $filename.Replace('_','-').Replace('?','_').Replace('*','_').Replace(' ','-').Replace('\','-').Replace('/','-').Replace(':','-').Replace('<','-').Replace('>','-').Replace('|','-').Replace('%','pct')
}

function GetAppNameAndFolder {
    Param(
        [string] $appFile
    )

    $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    Extract-AppFileToFolder -appFilename $appFile -appFolder $tmpFolder -generateAppJson
    $appJson = Get-Content -Path (Join-Path $tmpFolder 'app.json') -Encoding utf8 | ConvertFrom-Json
    $appJson.name
    (SanitizeFileName -filename $appJson.name).ToLower()
    Remove-Item -Path $tmpFolder -Recurse -Force
}

function GenerateDocsSite {
    Param(
        [string] $version,
        [string[]] $allVersions,
        [hashtable] $allApps,
        [string] $repoName,
        [string] $header,
        [string] $footer,
        [string] $defaultIndexMD,
        [string] $defaultReleaseMD,
        [string] $docsPath,
        [string] $logLevel,
        [switch] $hostIt
    )

    $indexTemplateRelativePath = '.aldoc/index.md'
    if ($version) {
        $thisTemplateRelativePath = '.aldoc/release.md'
        $thisDefaultMD = $defaultReleaseMD
    }
    else {
        $thisTemplateRelativePath = $indexTemplateRelativePath
        $thisDefaultMD = $defaultIndexMD
    }

    $indexTemplatePath = Join-Path $ENV:GITHUB_WORKSPACE $thisTemplateRelativePath
    if (-not (Test-Path $indexTemplatePath)) {
        $indexTemplatePath = Join-Path $ENV:GITHUB_WORKSPACE $indexTemplateRelativePath
    }
    if (Test-Path $indexTemplatePath) {
        $indexTemplate = Get-Content -Encoding utf8 -Path $indexTemplatePath -Raw
    }
    else {
        $indexTemplate = $thisDefaultMD
    }
    $indexContent = $indexTemplate.Replace('{REPOSITORY}',$ENV:GITHUB_REPOSITORY).Replace('{VERSION}',$version).Replace('{RELEASENOTES}',$releaseNotes).Replace('{INDEXTEMPLATERELATIVEPATH}',$thisTemplateRelativePath)

    $alDocPath = DownloadAlDoc
    $docfxPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -path $docfxPath -ItemType Directory | Out-Null
    try {
        $apps = @()
        # Generate new toc.yml and calculate apps - releases and projects
        $prefix = ''
        if ($version) {
            $prefix = "../../"
        }
        $newTocYml = @('items:')
        if ($allVersions.Count -gt 0) {
            $newTocYml += @("  - name: Releases","    items:","    - name: main","      href: $($prefix)index.html")
            foreach($ver in $allVersions) {
                $newTocYml += @("    - name: $ver","      href: $($prefix)releases/$ver/index.html")
            }
        }
        $allApps | ConvertTo-Json -Depth 99 | Out-Host
        if ($allApps.Keys.Count -eq 1 -and $allApps.Keys[0] -eq $repoName) {
            # Single prokect repo
            foreach($appFile in $allApps."$repoName") {
                $apps += @($appFile)
                $appName, $appFolder = GetAppNameAndFolder -appFile $appFile
                $newTocYml += @("  - name: $appName","    href: reference/$appFolder/toc.yml")
            }
        }
        else {
            # Multi project repo add all apps
            foreach($project in $allApps.Keys) {
                $newTocYml += @("  - name: $project",'    items:')
                foreach($appFile in $allApps."$project") {
                    $apps += @($appFile)
                    $appName, $appFolder = GetAppNameAndFolder -appFile $appFile
                    $newTocYml += @("    - name: $appName","      href: reference/$appFolder/toc.yml")
                }
            }
        }

        $arguments = @("init","--output ""$docfxpath""","--loglevel $loglevel","--targetpackages ""$($apps -join '","')""")
        Write-Host "invoke aldoc $arguments"
        CmdDo -command $aldocPath -arguments $arguments
        FixBackslashes -docfxPath $docfxPath

        # Update docfx.json
        Write-Host "Update docfx.json"
        $docfxJsonFile = Join-Path $docfxPath 'docfx.json'
        $docfxJson = Get-Content -Encoding utf8 -Path $docfxJsonFile | ConvertFrom-Json
        $docfxJson.build.globalMetadata._appName = $header
        $docfxJson.build.globalMetadata._appFooter = $footer
        $docfxJson | ConvertTo-Json -Depth 99 | Set-Content -Path $docfxJsonFile -Encoding utf8

        Write-Host "docfx.json:"
        Get-Content $docfxJsonFile | Out-Host

        # Create new toc.yml
        Write-Host "Create new toc.yml"
        $tocYmlFile = Join-Path $docfxpath 'toc.yml'

        Write-Host "ORGTOC:"
        Get-Content $tocYmlFile | Out-Host

        Set-Content -Path $tocYmlFile -Value ($newTocYml -join "`n") -Encoding utf8

        Write-Host "TOC:"
        Get-Content $tocYmlFile | Out-Host

        $apps | ForEach-Object {
            $arguments = @("build","--output ""$docfxpath""","--loglevel $loglevel","--source ""$_""")
            Write-Host "invoke aldoc $arguments"
            CmdDo -command $aldocPath -arguments $arguments
            FixBackslashes -docfxPath $docfxPath
        }

        # Set release notes
        Write-Host "Update index.md"
        $indexMdFile = Join-Path $docfxpath 'index.md'
        Set-Content -path $indexMdFile -value $indexContent -encoding utf8

        Write-Host "index.md:"
        Get-Content $indexMdFile | Out-Host


        $arguments = @("build", "--output ""$docsPath""", "--logLevel $loglevel", """$docfxJsonFile""")
        if ($hostIt) {
            $arguments += @('-s')
            Write-Host "Generate and host site"
        }
        Write-Host "invoke doxfx $arguments"
        CmdDo -command docfx -arguments $arguments
    }
    finally {
        Remove-Item -Path $docfxPath -Recurse -Force
    }
}

function CalculateProjectsAndApps {
    Param(
        [string] $tempFolder,
        [string[]] $projects,
        [string[]] $excludeProjects
    )

    if ($projects.Count -eq 0) { $projects = @('*') }
    $projectList = @($projects | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    $excludeProjectList = @($excludeProjects | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    foreach($mask in 'Apps','Dependencies') {
        $allApps = @{}
        Get-ChildItem -Path $tempFolder -Directory | ForEach-Object {
            if ($_.Name -match "^(.*)-main-$mask-(\d*\.\d*\.\d*\.\d*)$") {
                $project = $Matches[1]
                if ($projectList | Where-Object { $project -like $_ }) {
                    if (-not ($excludeProjectList | Where-Object { $project -like $_ })) {
                        $allApps."$project" = @()
                        Get-ChildItem -Path $_.FullName -Filter '*.app' | ForEach-Object {
                            $allApps."$project" += @($_.FullName)
                        }
                    }
                }
            }
        }
        $allApps
    }
}